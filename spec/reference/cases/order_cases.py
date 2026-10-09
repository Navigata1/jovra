"""ADR0030 paired Rules/As-Played vectors; assertions are hand-derived before the reference changes."""
import copy
import json
from .common import CLUB_BO3, TB_ONLY_10, singles, doubles, fmt, tb_set
from jovra_ref import conformance

ORDER = 11


def points(winners):
    return [{"id": f"p{i:02}", "seq": i, "type": "point", "reviewed": {
        "winner": w, "endType": "unknown", "provenance": "manual", "source": "user"}}
        for i, w in enumerate(winners, 1)]


def add(log, kind, **fields):
    event = {"id": f"o{len(log)+1:02}", "seq": len(log)+1, "type": kind, **fields}
    log.append(event)
    return event["id"]


def server(log, target, who, continuation="pointOnly", **extra):
    if continuation != "pointOnly": extra["discoveryAfterPointId"] = target
    return add(log, "serverOverride", targetPointId=target, server=who, continuation=continuation,
               provenance="reviewed", source="user", **extra)


def doubles_setup(log, fmt=CLUB_BO3):
    for event in log: event["seq"] += 1
    log.insert(0, {"id": "order", "seq": 1, "type": "doublesOrder", "setIndex": 0,
                   "firstServer": "ann", "secondServer": "ben", "deuceReceivers": {"A": "ann", "B": "ben"}})
    return doubles(fmt)


def scenarios():
    result = []
    log = points("AAAA")
    for i in range(1, 5): server(log, f"p{i:02}", "alex", "completedStandardGame" if i == 4 else "pointOnly")
    result.append(("completed-singles-game", singles(CLUB_BO3), log,
                   [("fold.next.server", "alex", "jon"), ("fold.points[0].server", "jon", "alex"),
                    ("fold.next.before.games", {"A": 1, "B": 0}, {"A": 1, "B": 0}),
                    ("fold.match.pointsPlayed", 4, 4), ("stats.sides.A.servicePoints", 4, 0),
                    ("stats.sides.B.servicePoints", 0, 4)]))
    log = points("AA"); server(log, "p01", "alex")
    result.append(("midgame-observation", singles(CLUB_BO3), log,
                   [("fold.points[0].server", "jon", "alex"), ("fold.points[1].server", "jon", "jon"),
                    ("fold.next.server", "jon", "jon")]))
    log = points("AAAABBBB"); setup = doubles_setup(log)
    for i in range(1, 5):
        server(log, f"p{i:02}", "amy", "completedStandardGame" if i == 4 else "pointOnly",
               **({"rotation": ["amy", "ben", "ann", "bob"]} if i == 4 else {}))
    result.append(("doubles-partner-order", setup, log,
                   [("fold.next.server", "amy", "ann"), ("fold.points[4].server", "ben", "ben"),
                    ("fold.points[0].server", "ann", "amy")]))
    log = points("AAAA"); setup = doubles_setup(log)
    for i in range(1, 5):
        server(log, f"p{i:02}", "ben", "completedStandardGame" if i == 4 else "pointOnly",
               **({"rotation": ["ben", "ann", "bob", "amy"]} if i == 4 else {}))
    result.append(("doubles-opposite-team", setup, log,
                   [("fold.next.server", "ben", "ann"), ("fold.points[0].server", "ann", "ben")]))
    log = points("A"); server(log, "p01", "alex", "oddTiebreak")
    result.append(("odd-tiebreak-anchor", singles(TB_ONLY_10), log,
                   [("fold.next.server", "alex", "jon"), ("fold.next.before.points", {"A": 1, "B": 0}, {"A": 1, "B": 0})]))
    log = points("AA"); server(log, "p02", "jon", "oddTiebreak")
    result.append(("even-tiebreak-context-changed", singles(TB_ONLY_10), log,
                   [("fold.next.server", "alex", "alex"), ("fold.points[1].server", "alex", "jon"),
                    ("fold.conflicts[0].type", "serverMismatch", "overrideContextChanged")]))
    log = points("AAAABBBBA"); setup = doubles_setup(log)
    add(log, "receiverOverride", targetPointId="p01", receivingSide="B", deuceReceiver="bob", provenance="reviewed", source="user")
    result.append(("receiver-game-expiry", setup, log,
                   [("fold.points[0].receiver", "ben", "bob"), ("fold.points[1].receiver", "bob", "ben"),
                    ("fold.points[8].receiver", "ben", "ben")]))
    log = points("AAAB"); server(log, "p04", "alex", "completedStandardGame")
    result.append(("standard-boundary-context-changed", singles(CLUB_BO3), log,
                   [("fold.points[3].server", "jon", "alex"), ("fold.next.server", "jon", "jon"),
                    ("fold.conflicts[0].type", "serverMismatch", "overrideContextChanged")]))
    short = fmt("custom", 2, set_rule=tb_set(1, 1, 7))
    log = points("AAAABBBBAAAAAAABBBBA"); setup = doubles_setup(log, short)
    add(log, "receiverOverride", targetPointId="p09", receivingSide="B", deuceReceiver="bob", provenance="reviewed", source="user")
    result.append(("receiver-tiebreak-expiry", setup, log,
                   [("fold.points[8].receiver", "ben", "bob"), ("fold.points[19].receiver", "ben", "ben")]))
    for explicit in (False, True):
        log = points("AAAAAAAA"); setup = doubles_setup(log, short)
        for i in range(1, 5):
            server(log, f"p{i:02}", "amy", "completedStandardGame" if i == 4 else "pointOnly",
                   **({"rotation": ["amy", "ben", "ann", "bob"]} if i == 4 else {}))
        if explicit:
            add(log, "doublesOrder", setIndex=1, firstServer="ann", secondServer="ben", deuceReceivers={"A": "ann", "B": "ben"})
        result.append(("explicit-new-set-order" if explicit else "new-set-order-carry", setup, log,
                       [("fold.next.server", "ann", "ann" if explicit else "amy"),
                        ("fold.next.set", 1, 1), ("fold.match.pointsPlayed", 8, 8)]))
    return result


def generate(ctx):
    count = 0
    for index, (title, setup, log, hand_assertions) in enumerate(scenarios()):
        for mode_index, mode in enumerate(("rules", "asPlayed")):
            fixture_input = {**copy.deepcopy(setup), "log": copy.deepcopy(log), "resolutionMode": mode}
            assertions = [{"checkpoint": 0, "path": path, "equals": values[mode_index]}
                          for path, *values in hand_assertions]
            checkpoints = conformance.run_scoring(fixture_input, [log[-1]["seq"]])
            failures = conformance.check_assertions(checkpoints, assertions)
            if failures: raise ValueError(f"{title}/{mode}: {failures}")
            fixture_id = f"O{index*2+mode_index+1:02}-{title}-{'rules' if mode == 'rules' else 'as-played'}"
            ctx.write_json(ctx.fixtures / "scoring" / f"{fixture_id}.json", {
                "schemaVersion": "1.2.0", "kind": "jovra.fixture.scoring", "id": fixture_id,
                "title": f"Reviewed order: {title}; {mode}", "covers": ["ADR0030", "Rule27c-e", mode],
                "input": fixture_input, "assertions": assertions, "checkpoints": checkpoints})
            count += 1
    negative = []
    log = points("A"); server(log, "missing", "alex")
    negative.append(("override-target-missing", singles(CLUB_BO3), log, "overrideTargetMissing"))
    log = points("A"); target = server(log, "p01", "alex"); log[-1]["targetPointId"] = target
    negative.append(("override-target-not-prior-point", singles(CLUB_BO3), log, "overrideTargetInvalid"))
    log = points("A"); target = server(log, "p01", "zed"); add(log, "void", target=target)
    negative.append(("unknown-player-voided-override", singles(CLUB_BO3), log, "unknownPlayer"))
    log = points("AAAA"); setup = doubles_setup(log)
    server(log, "p04", "amy", "completedStandardGame", rotation=["amy", "ann", "ben", "bob"])
    negative.append(("nonalternating-reviewed-rotation", setup, log, "overrideRotationInvalid"))
    log = points("A"); setup = doubles_setup(log)
    add(log, "receiverOverride", targetPointId="p01", receivingSide="B", deuceReceiver="ann", provenance="reviewed", source="user")
    negative.append(("receiver-on-wrong-team", setup, log, "receiverOverrideInvalid"))
    log = points("A")
    add(log, "receiverOverride", targetPointId="p01", receivingSide="B", deuceReceiver="alex", provenance="reviewed", source="user")
    negative.append(("singles-receiver-override", singles(CLUB_BO3), log, "receiverOverrideInvalid"))
    log = points("AAAA"); server(log, "p04", "alex", "completedStandardGame"); log[-1]["discoveryAfterPointId"] = "p03"
    negative.append(("discovery-endpoint-not-target", singles(CLUB_BO3), log, "overrideMetadataInvalid"))
    for index, (title, setup, log, code) in enumerate(negative, 11):
        fixture_input = {**setup, "log": log, "resolutionMode": "asPlayed"}
        actual = conformance.run_scoring_error(fixture_input)
        if actual != code: raise ValueError(f"{title}: expected {code}, got {actual}")
        fixture_id = f"E{index:02}-{title}"
        ctx.write_json(ctx.fixtures / "scoring" / f"{fixture_id}.json", {
            "schemaVersion": "1.2.0", "kind": "jovra.fixture.scoring", "id": fixture_id,
            "title": f"Reviewed order structural refusal: {title}", "covers": ["ADR0030", code],
            "input": fixture_input, "expectError": {"code": code}})
        count += 1
    # A real typed document round-trip seam, visibly sample; source sample remains untouched.
    doc = json.loads((ctx.fixtures / "sample/jon-vs-alex.session.json").read_text())
    doc["id"] = "sample-reviewed-order"
    doc["title"] = "Sample reviewed serving order"
    doc["schemaVersion"] = "1.2.0"
    doc["match"]["resolutionMode"] = "asPlayed"
    first = doc["match"]["log"][0]
    doc["match"]["log"].append({"id": "reviewed-order", "seq": doc["match"]["log"][-1]["seq"]+1,
        "type": "serverOverride", "targetPointId": first["id"], "server": doc["players"][0]["id"],
        "continuation": "pointOnly", "provenance": "reviewed", "source": "user"})
    ctx.write_json(ctx.fixtures / "records/session.order-overrides.json", doc)
    return count + 1
