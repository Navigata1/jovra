#!/usr/bin/env python3
"""ADR0030 public-seam cases. Expectations are hand-derived before the reference changes.

The same point log is folded in Rules and As-Played views. This is a focused contract amendment,
not a native scorer or automated Rule27 officiating. Full fixture outputs will be generated only
when these independent assertions agree. Run: python3 -m unittest discover -s scripts/spec -p test_order_overrides.py -v
"""
from __future__ import annotations

import copy
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "spec/reference"))
sys.path.insert(0, str(ROOT / "scripts/spec"))
from jsonschema_subset import SchemaSet
from cases.common import CLUB_BO3, TB_ONLY_10, singles, doubles
from jovra_ref import scoring, references
from jovra_ref.log import LogError


def points(winners):
    return [{"id": f"p{i:02}", "seq": i, "type": "point", "reviewed": {
        "winner": w, "endType": "unknown", "provenance": "manual", "source": "user"}}
        for i, w in enumerate(winners, 1)]


def add(log, kind, **fields):
    event = {"id": f"o{len(log)+1:02}", "seq": len(log)+1, "type": kind, **fields}
    log.append(event)
    return event["id"]


def server(log, point, who, continuation="pointOnly", **fields):
    if continuation != "pointOnly": fields["discoveryAfterPointId"] = point
    return add(log, "serverOverride", targetPointId=point, server=who, continuation=continuation,
               provenance="reviewed", source="user", **fields)


def views(setup, log):
    result = {}
    for mode in ("rules", "asPlayed"):
        config = copy.deepcopy(setup)
        config["resolutionMode"] = mode
        result[mode] = scoring.fold(config, log)
    return result["rules"], result["asPlayed"]


def doubles_setup(log, fmt=CLUB_BO3):
    # Per-set metadata is unplaced; its seq precedes the points but point IDs remain stable.
    order = {"id": "order", "seq": 1, "type": "doublesOrder", "setIndex": 0,
             "firstServer": "ann", "secondServer": "ben", "deuceReceivers": {"A": "ann", "B": "ben"}}
    for event in log: event["seq"] += 1
    log.insert(0, order)
    return doubles(fmt)


class ReviewedOrderPairs(unittest.TestCase):
    def test_singles_completed_game_preserves_observation_and_reanchors_next_game(self):
        log = points("AAAA")
        for i in range(1, 5):
            server(log, f"p{i:02}", "alex", "completedStandardGame" if i == 4 else "pointOnly")
        rules, played = views(singles(CLUB_BO3), log)
        self.assertEqual([p["server"] for p in rules["points"]], ["jon"]*4)
        self.assertEqual([p["server"] for p in played["points"]], ["alex"]*4)
        self.assertEqual(rules["next"]["server"], "alex")
        self.assertEqual(played["next"]["server"], "jon")
        self.assertEqual(rules["next"]["before"]["games"], {"A": 1, "B": 0})
        self.assertEqual(played["next"]["before"]["games"], {"A": 1, "B": 0})
        self.assertEqual(rules["match"]["pointsPlayed"], played["match"]["pointsPlayed"])
        self.assertEqual([c["type"] for c in rules["conflicts"]], ["serverMismatch"]*4)

    def test_midgame_point_identity_does_not_infer_persistent_rotation(self):
        log = points("AA")
        server(log, "p01", "alex")
        rules, played = views(singles(CLUB_BO3), log)
        self.assertEqual(rules["points"][0]["server"], "jon")
        self.assertEqual(played["points"][0]["server"], "alex")
        self.assertEqual(played["points"][1]["server"], "jon")
        self.assertEqual(played["next"]["server"], "jon")

    def test_doubles_reviewed_rotation_preserves_explicit_partner_order(self):
        log = points("AAAABBBB")
        config = doubles_setup(log)
        for i in range(1, 5):
            server(log, f"p{i:02}", "amy", "completedStandardGame" if i == 4 else "pointOnly",
                   **({"rotation": ["amy", "ben", "ann", "bob"]} if i == 4 else {}))
        rules, played = views(config, log)
        self.assertEqual(rules["next"]["server"], "amy")
        self.assertEqual(played["next"]["server"], "ann")
        self.assertEqual(played["points"][4]["server"], "ben")

    def test_tiebreak_odd_discovery_retains_block_phase(self):
        log = points("A")
        server(log, "p01", "alex", "oddTiebreak")
        rules, played = views(singles(TB_ONLY_10), log)
        self.assertEqual(rules["next"]["server"], "alex")
        self.assertEqual(played["next"]["server"], "jon")
        self.assertEqual(played["next"]["before"]["points"], {"A": 1, "B": 0})

    def test_even_tiebreak_endpoint_keeps_observation_but_refuses_inferred_anchor(self):
        log = points("AA")
        server(log, "p02", "jon", "oddTiebreak")
        rules, played = views(singles(TB_ONLY_10), log)
        self.assertEqual(played["points"][1]["server"], "jon")
        self.assertEqual(played["next"]["server"], rules["next"]["server"])
        self.assertIn("overrideContextChanged", [c["type"] for c in played["conflicts"]])

    def test_receiver_override_expires_after_one_game(self):
        log = points("AAAABBBBA")
        config = doubles_setup(log)
        add(log, "receiverOverride", targetPointId="p01", receivingSide="B", deuceReceiver="bob",
            provenance="reviewed", source="user")
        rules, played = views(config, log)
        self.assertEqual(rules["points"][0]["receiver"], "ben")
        self.assertEqual(played["points"][0]["receiver"], "bob")
        self.assertEqual(played["points"][1]["receiver"], "ben")
        self.assertEqual(played["points"][8]["receiver"], "ben")
        self.assertIn("receiverMismatch", [c["type"] for c in rules["conflicts"]])

    def test_override_void_redo_keeps_original_observation(self):
        log = points("A")
        observation = server(log, "p01", "alex")
        undo = add(log, "void", target=observation)
        _, played = views(singles(CLUB_BO3), log)
        self.assertEqual(played["points"][0]["server"], "jon")
        add(log, "void", target=undo)
        _, played = views(singles(CLUB_BO3), log)
        self.assertEqual(played["points"][0]["server"], "alex")

    def test_missing_override_target_is_stable_structural_error(self):
        log = points("A")
        server(log, "absent", "alex")
        with self.assertRaises(LogError) as caught: scoring.fold(singles(CLUB_BO3), log)
        self.assertEqual(caught.exception.code, "overrideTargetMissing")


    def test_target_supersede_leaves_observation_inert_until_explicitly_reentered(self):
        log = points("A")
        server(log, "p01", "alex")
        add(log, "point", supersedes="p01", reviewed={"winner": "A", "endType": "unknown",
            "provenance": "manual", "source": "user"})
        _, played = views(singles(CLUB_BO3), log)
        self.assertEqual(len(played["points"]), 1)
        self.assertEqual(played["points"][0]["server"], "jon")

    def test_target_void_keeps_override_inert_and_redo_restores_it(self):
        log = points("A")
        server(log, "p01", "alex")
        undo = add(log, "void", target="p01")
        _, played = views(singles(CLUB_BO3), log)
        self.assertEqual(played["points"], [])
        add(log, "void", target=undo)
        _, played = views(singles(CLUB_BO3), log)
        self.assertEqual(played["points"][0]["server"], "alex")

    def test_boundary_correction_keeps_point_observation_and_raises_conflict(self):
        log = points("AAAB")
        server(log, "p04", "alex", "completedStandardGame")
        _, played = views(singles(CLUB_BO3), log)
        self.assertEqual(played["points"][3]["server"], "alex")
        self.assertEqual(played["next"]["server"], "jon")
        self.assertIn("overrideContextChanged", [c["type"] for c in played["conflicts"]])

    def test_structural_rotation_team_and_reference_controls(self):
        controls = []
        log = points("AAAA"); setup = doubles_setup(log)
        server(log, "p04", "amy", "completedStandardGame", rotation=["amy", "ann", "ben", "bob"])
        controls.append((setup, log, "overrideRotationInvalid"))
        log = points("A"); setup = doubles_setup(log)
        add(log, "receiverOverride", targetPointId="p01", receivingSide="B", deuceReceiver="ann",
            provenance="reviewed", source="user")
        controls.append((setup, log, "receiverOverrideInvalid"))
        log = points("A"); server(log, "p01", "zed")
        controls.append((singles(CLUB_BO3), log, "unknownPlayer"))
        log = points("A"); observation = server(log, "p01", "alex")
        log[-1]["targetPointId"] = observation
        controls.append((singles(CLUB_BO3), log, "overrideTargetInvalid"))
        for setup, log, code in controls:
            with self.subTest(code=code):
                with self.assertRaises(LogError) as caught: scoring.fold(setup, log)
                self.assertEqual(caught.exception.code, code)


    def test_explicit_fold_mode_overrides_document_preference(self):
        log = points("A"); server(log, "p01", "alex")
        setup = singles(CLUB_BO3); setup["resolutionMode"] = "asPlayed"
        rules = scoring.fold(setup, log, mode="rules")
        self.assertEqual(rules["points"][0]["server"], "jon")
        self.assertEqual(setup["resolutionMode"], "asPlayed")


    def test_ordinary_record_integrity_rejects_dangling_override_targets_and_players(self):
        doc = json.loads((ROOT / "spec/fixtures/records/session.order-overrides.json").read_text())
        self.assertEqual(references.session_problems(doc), [])
        event = doc["match"]["log"][-1]
        event["targetPointId"] = "unknown-point"
        event["server"] = "unknown-player"
        problems = references.session_problems(doc)
        self.assertTrue(any("targetPointId" in p for p in problems))
        self.assertTrue(any("server" in p for p in problems))

    def test_version_guards_and_closed_objects(self):
        schemas = SchemaSet(ROOT / "spec/schemas")
        doc = json.loads((ROOT / "spec/fixtures/sample/jon-vs-alex.session.json").read_text())
        doc["match"]["resolutionMode"] = "asPlayed"
        for version in ("1.0.0", "1.1.0", "01.01.000"):
            doc["schemaVersion"] = version
            self.assertTrue(schemas.validate(doc, "session.schema.json"))
        doc["schemaVersion"] = "1.2.0"
        self.assertEqual(schemas.validate(doc, "session.schema.json"), [])
        first = doc["match"]["log"][0]
        event = {"id": "override", "seq": doc["match"]["log"][-1]["seq"]+1,
                 "type": "serverOverride", "targetPointId": first["id"], "server": doc["players"][0]["id"],
                 "continuation": "pointOnly", "provenance": "reviewed", "source": "user"}
        doc["match"]["log"].append(event)
        self.assertEqual(schemas.validate(doc, "session.schema.json"), [])
        event["unexpected"] = True
        self.assertTrue(schemas.validate(doc, "session.schema.json"))
        del event["unexpected"]
        event["discoveryAfterPointId"] = first["id"]
        self.assertTrue(schemas.validate(doc, "session.schema.json"))


if __name__ == "__main__": unittest.main()
