"""Cross-record rules for one Studio project: the records must agree with each other, not just with their schemas.

An EDL's source snapshot must equal the trusted SourceManifest and reviewed SyncMap; its live segments must sit inside
keeper views with every contact protected; a delivered film must be the render of a plan that exists; a job, its
reservation and its quote must share one idempotency key, plan revision and output spec; every artifact a job lists
must exist, belong to it and (for ready) be verified; a ProjectLock pins the manifest hash; the ReferenceCatalog agrees
with the lessons, the lock's participants and the current event revision.
"""

from __future__ import annotations

from . import ledger
from .core import Reject, canonical_sha256, output_spec_sha256, require
from .edl import clean_alternate

USABLE_SYNC_STATES = {"reference", "reviewed"}
output_spec_hash = output_spec_sha256


def trusted_sources(b: dict) -> dict:
    """The sources offered for cutting, with the snapshot and coverage a plan must copy exactly. A match source is
    offered only when its manifest records exactly one segment and the sync map has exactly one piece, for that
    segment, in a reference or reviewed state (the reference cross-check covers single-segment sources; its coverage is
    the whole render proxy, so it is offered only when the one piece maps the whole recording). A restarted source
    (two or more manifest segments) is never offered here, even if the sync map omits the other pieces: anything else
    is absent, so a plan naming it is untrustedSource."""
    maps = {s["sourceId"]: s["pieces"] for s in b["syncMap"]["sources"]}
    out = {}
    for src in b["manifest"]["sources"]:
        proxies = [p for p in src["proxies"] if p["class"] == "render"]
        if len(proxies) != 1 or src["verification"]["status"] != "verified":
            continue
        proxy = proxies[0]
        if src["role"] == "broll":
            coverage = [{"inFrame": 0, "outFrame": proxy["frameCount"], "sessionStartUs": None, "rate": None}]
        else:
            pieces = maps.get(src["sourceId"])
            if (pieces is None or len(pieces) != 1 or len(src["segments"]) != 1
                    or pieces[0]["segmentId"] != src["segments"][0]["segmentId"]
                    or pieces[0]["sourceDurationUs"] != src["segments"][0]["durationUs"]
                    or pieces[0]["state"] not in USABLE_SYNC_STATES):
                continue
            t = pieces[0]["transform"]
            coverage = [{"inFrame": 0, "outFrame": proxy["frameCount"], "sessionStartUs": t["offsetUs"], "rate": t["rate"]}]
        out[src["sourceId"]] = {
            "sha256": src["original"]["sha256"], "role": src["role"], "hasAudio": src["original"]["audio"] is not None,
            "proxy": {"fps": proxy["fps"], "width": proxy["width"], "height": proxy["height"],
                      "frameCount": proxy["frameCount"], "ptsTableSha256": proxy["ptsTableSha256"]},
            "coverage": coverage}
    return out


def capture_hints(manifest: dict, smap: dict) -> dict:
    """Capture hints as match-clock offsets of each segment's zero: {sourceId: {segmentId: offsetUs}}.

    The journal puts every segment of one device on that device's host clock (fileZeroHostNs); captureHints.roomOffsetUs
    is the room clock minus the device host clock, measured at pairing. A segment's room time is
    fileZeroHostNs / 1000 + roomOffsetUs (half-up to whole microseconds). Its hint is that room time minus the room time
    of the reference segment, plus the reference segment's match offset. On the reference device itself the room
    offset cancels, so its restarted segments need only the journal. A segment with no journal (imports) or a device
    with no room offset gets no hint. Hints are priors, never synchronization (multicam-sync.md section 3.4)."""
    from fractions import Fraction
    from .core import round_half_up
    ref_id = smap["matchClock"]["referenceSourceId"]
    ref_seg = smap["matchClock"]["referenceSegmentId"]
    by_id = {s["sourceId"]: s for s in manifest["sources"]}
    ref_src = by_id.get(ref_id)
    ref_piece = next((p for s in smap["sources"] if s["sourceId"] == ref_id for p in s["pieces"]
                      if p["segmentId"] == ref_seg), None)
    ref_g = next((g for g in ref_src["segments"] if g["segmentId"] == ref_seg), None) if ref_src else None
    if ref_g is None or ref_g["fileZeroHostNs"] is None or ref_piece is None or ref_piece["transform"] is None:
        return {}
    ref_offset = ref_piece["transform"]["offsetUs"]
    out: dict = {}
    for src in manifest["sources"]:
        if src["role"] != "match":
            continue
        same_device = src["sourceId"] == ref_id
        room = src["captureHints"]["roomOffsetUs"]
        ref_room = ref_src["captureHints"]["roomOffsetUs"]
        if not same_device and (room is None or ref_room is None):
            continue
        for g in src["segments"]:
            if g["fileZeroHostNs"] is None:
                continue
            delta_ns = g["fileZeroHostNs"] - ref_g["fileZeroHostNs"]
            delta_room = 0 if same_device else room - ref_room
            out.setdefault(src["sourceId"], {})[g["segmentId"]] = (
                round_half_up(Fraction(delta_ns, 1000)) + delta_room + ref_offset)
    return out


def point_windows(ref: dict, keepers: dict) -> list | None:
    """Where a point-event overlay may be shown over play: the session windows [startUs, endUs] of every keeper whose
    eventRefs carry that point, sorted. None for any other origin (a score state, a stat, a note), which is not bound
    to one rally. An empty list means the point is in no keeper, so it can be shown over no live or replayed play."""
    if ref["origin"]["recordKind"] != "point-event":
        return None
    point = ref["origin"]["recordId"]
    return sorted([k["session"]["startUs"], k["session"]["endUs"]] for k in keepers["keepers"] if point in k["eventRefs"])


def edl_context(b: dict) -> dict:
    """The trusted context an EDL is validated against (edl.validate requires every key): current revisions, the
    sources offered for cutting, keeper and B-roll ids, and the ReferenceCatalog's overlay targets, notes, consents
    and rights. Built from stored records only; nothing here comes from the plan."""
    manifest, smap, keepers, brolls, refs = b["manifest"], b["syncMap"], b["keepers"], b["brolls"], b["references"]
    contacts: dict[str, list] = {}
    for k in keepers["keepers"]:
        for c in k["contacts"]:
            contacts.setdefault(c["sourceId"], []).append(c["frame"])
    return {
        "projectId": manifest["projectId"],
        "current": {"sourceManifestRevision": manifest["revision"], "syncRevision": smap["revision"],
                    "eventRevision": keepers["eventRevision"], "keeperCatalogRevision": keepers["revision"],
                    "brollCatalogRevision": brolls["revision"]},
        "sources": trusted_sources(b),
        "keepers": [k["keeperId"] for k in keepers["keepers"]],
        "contacts": {sid: sorted(set(frames)) for sid, frames in sorted(contacts.items())},
        "brolls": [i["brollId"] for i in brolls["items"]],
        "references": {r["refId"]: {"kind": r["kind"], "provenance": r["provenance"], "eventRevision": r["eventRevision"],
                                    "pointWindows": point_windows(r, keepers)}
                       for r in refs["references"]},
        "consents": {c["consentRecordId"]: {"participantId": c["participantId"], "scope": list(c["scope"]),
                                            "granted": c["granted"]} for c in refs["consents"]},
        "rights": {r["rightsRecordId"]: {"assetId": r["assetId"], "scope": list(r["scope"])} for r in refs["rights"]},
    }


def render_proxy(src: dict) -> dict:
    proxies = [p for p in src["proxies"] if p["class"] == "render"]
    require(len(proxies) == 1, "missingProxy", f"{src['sourceId']} needs exactly one render proxy")
    return proxies[0]


def check_lock(b: dict) -> None:
    lock, manifest = b["lock"], b["manifest"]
    require(lock["sourceManifest"]["sha256"] == canonical_sha256(manifest), "lockMismatch",
            "the ProjectLock pins a different SourceManifest")
    require(lock["sourceManifest"]["revision"] == manifest["revision"]
            and lock["eventRevision"] == b["keepers"]["eventRevision"]
            and lock["syncRevision"] == b["syncMap"]["revision"], "lockMismatch", "lock revisions are not current")
    ids = {s["sourceId"] for s in manifest["sources"]}
    require(all(r["sourceId"] in ids for r in lock["sourceRights"]), "lockMismatch", "rights for an unknown source")


def check_sync_against_manifest(b: dict) -> None:
    manifest, smap = b["manifest"], b["syncMap"]
    by_id = {s["sourceId"]: s for s in manifest["sources"]}
    require(smap["sourceManifestRevision"] == manifest["revision"], "staleRevision", "sync map built on an older manifest")
    primary = [s["sourceId"] for s in manifest["sources"] if s["isPrimary"]][0]
    require(smap["matchClock"]["referenceSourceId"] == primary, "badReference", "the reference is the primary source")
    for p in smap["placements"]:
        src = by_id.get(p["sourceId"])
        require(src is not None and src["role"] == "match" and src["slot"] == p["slot"], "placementMismatch",
                f"placement of {p['sourceId']} disagrees with the manifest")
    mapped = {s["sourceId"]: s for s in smap["sources"]}
    for s in smap["sources"]:
        src = by_id.get(s["sourceId"])
        require(src is not None and src["role"] == "match", "placementMismatch",
                f"{s['sourceId']}: the sync map names a source that is not a recorded match source")
    for src in manifest["sources"]:
        if src["role"] != "match":
            continue
        # exactly one piece per recorded segment: a sync map cannot drop a restarted segment and let the one piece it
        # keeps stand for the whole recording (an unmapped segment is a failed piece, never an omitted one)
        s = mapped.get(src["sourceId"])
        require(s is not None, "unmappedSegment", f"{src['sourceId']}: a recorded match source has no sync map entry")
        segs = {g["segmentId"]: g for g in src["segments"]}
        piece_ids = [p["segmentId"] for p in s["pieces"]]
        require(len(piece_ids) == len(set(piece_ids)) and set(piece_ids) == set(segs), "unmappedSegment",
                f"{src['sourceId']}: sync pieces {sorted(piece_ids)} must be exactly one per recorded segment "
                f"{sorted(segs)}")
        for piece in s["pieces"]:
            seg = segs[piece["segmentId"]]
            require(seg["durationUs"] == piece["sourceDurationUs"], "placementMismatch",
                    f"{s['sourceId']}/{piece['segmentId']} does not match a recorded segment")


def check_catalogs(b: dict) -> None:
    by_id = {s["sourceId"]: s for s in b["manifest"]["sources"]}
    for k in b["keepers"]["keepers"]:
        for v in k["views"]:
            src = by_id.get(v["sourceId"])
            require(src is not None and src["role"] == "match"
                    and v["window"]["outFrame"] <= render_proxy(src)["frameCount"], "unknownSource",
                    f"keeper {k['keeperId']} view outside a match source")
    for i in b["brolls"]["items"]:
        src = by_id.get(i["sourceId"])
        require(src is not None and src["role"] == "broll" and i["window"]["outFrame"] <= render_proxy(src)["frameCount"],
                "unknownSource", f"B-roll {i['brollId']} outside a B-roll source")


def check_plan_against_trusted(plan: dict, b: dict) -> None:
    by_id = {s["sourceId"]: s for s in b["manifest"]["sources"]}
    maps = {s["sourceId"]: s["pieces"] for s in b["syncMap"]["sources"]}
    keepers = {k["keeperId"]: k for k in b["keepers"]["keepers"]}
    brolls = {i["brollId"]: i for i in b["brolls"]["items"]}
    for s in plan["sources"]:
        src = by_id[s["id"]]
        proxy = render_proxy(src)
        snapshot = {"fps": proxy["fps"], "width": proxy["width"], "height": proxy["height"],
                    "frameCount": proxy["frameCount"], "ptsTableSha256": proxy["ptsTableSha256"]}
        require(s["role"] == src["role"] and s["proxy"] == snapshot and s["hasAudio"] == (src["original"]["audio"] is not None),
                "untrustedSource", f"{s['id']}: plan snapshot differs from the trusted manifest")
        if s["role"] == "broll":
            expect = [{"inFrame": 0, "outFrame": proxy["frameCount"], "sessionStartUs": None, "rate": None}]
        else:
            pieces = maps.get(s["id"])
            require(pieces is not None and len(pieces) == 1 and len(src["segments"]) == 1
                    and pieces[0]["segmentId"] == src["segments"][0]["segmentId"]
                    and pieces[0]["sourceDurationUs"] == src["segments"][0]["durationUs"], "unsupportedCoverage",
                    f"{s['id']}: the reference cross-check covers single-segment sources only, mapped by their one piece")
            piece = pieces[0]
            require(piece["state"] in USABLE_SYNC_STATES, "unreviewedSync",
                    f"{s['id']}: sync state {piece['state']} is not offered for cutting")
            expect = [{"inFrame": 0, "outFrame": proxy["frameCount"], "sessionStartUs": piece["transform"]["offsetUs"],
                       "rate": piece["transform"]["rate"]}]
        require(s["coverage"] == expect, "coverageMismatch", f"{s['id']}: coverage is not the reviewed sync map's")
    require(plan["projectId"] == b["manifest"]["projectId"], "projectMismatch", f"{plan['planId']}: another project")
    refs = {r["refId"]: r for r in b["references"]["references"]}
    by_seg = {seg["id"]: seg for seg in plan["segments"]}
    for seg in plan["segments"]:
        # a point's score or metric over live or replayed play names that point's keeper: the live segment (or the
        # live original a replay re-shows) must cut a keeper whose eventRefs carry the point (edl.validate checks the
        # same binding through the keeper session windows, so a segment naming no keeper is still bound)
        live = seg if seg["op"] == "live" else by_seg.get(seg.get("replayOf")) if seg["op"] == "replay" else None
        for o in seg.get("overlayRefs", []):
            stored = refs.get(o["refId"])
            if live is None or o["kind"] not in ("score", "metric") or stored is None \
                    or stored["origin"]["recordKind"] != "point-event":
                continue
            k = keepers.get(live["keeperId"]) if live["keeperId"] is not None else None
            if k is not None:
                require(stored["origin"]["recordId"] in k["eventRefs"], "overlayOutsideMoment",
                        f"{seg['id']}: {o['refId']} is not a point of keeper {k['keeperId']}")
    for seg in plan["segments"]:
        if seg["op"] == "live" and seg["keeperId"] is not None:
            k = keepers[seg["keeperId"]]
            views = [v for v in k["views"] if v["sourceId"] == seg["sourceId"]]
            require(views and views[0]["window"]["inFrame"] <= seg["sourceInFrame"]
                    and seg["sourceOutFrame"] <= views[0]["window"]["outFrame"], "outsideKeeper",
                    f"{seg['id']}: window is not inside keeper {k['keeperId']}'s view")
        if seg["op"] == "live":
            # every stored contact in the window, from any keeper: naming no keeper never switches protection off
            for k in keepers.values():
                for c in k["contacts"]:
                    if c["sourceId"] == seg["sourceId"] and seg["sourceInFrame"] <= c["frame"] < seg["sourceOutFrame"]:
                        require(any(w["inFrame"] <= c["frame"] < w["outFrame"] for w in seg["protectedFrames"]),
                                "contactUnprotected", f"{seg['id']}: contact {c['frame']} is not protected")
        if seg["op"] == "broll":
            item = brolls[seg["brollId"]]
            require(item["sourceId"] == seg["sourceId"] and item["window"]["inFrame"] <= seg["sourceInFrame"]
                    and seg["sourceOutFrame"] <= item["window"]["outFrame"], "outsideBroll",
                    f"{seg['id']}: window is not inside B-roll item {item['brollId']}")


def check_clean_pair(primary: dict, clean: dict) -> None:
    require(clean == clean_alternate(primary), "cleanAlternateMismatch",
            f"{clean['planId']} is not clean_alternate({primary['planId']})")


def check_artifact_against_plan(art: dict, plans: list, jobs: dict) -> dict:
    by_hash = {canonical_sha256(p): p for p in plans}
    plan = by_hash.get(art["bindings"]["editPlanSha256"])
    require(plan is not None, "unknownPlan", f"{art['artifactId']}: no plan has the bound edit-plan hash")
    m, o = art["media"], plan["output"]
    require((m["fps"], m["width"], m["height"], m["durationFrames"]) == (o["fps"], o["width"], o["height"], o["totalFrames"]),
            "artifactMismatch", "the film's clock, size or length differs from its plan")
    require([(c["id"], c["templateId"], c["startFrame"]) for c in art["chapters"]]
            == [(c["id"], c["templateId"], c["outputInFrame"]) for c in plan["chapters"]], "artifactMismatch",
            "chapters differ from the plan")
    bd, pb = art["bindings"], plan["bindings"]
    require(bd["sourceManifestRevision"] == pb["sourceManifestRevision"] and bd["syncRevision"] == pb["syncRevision"]
            and bd["eventRevision"] == pb["eventRevision"]
            and bd["profile"] == {"id": pb["profileId"], "revision": pb["profileRevision"]}
            and sorted(bd["sourceSha256s"]) == sorted(s["sha256"] for s in plan["sources"]), "artifactMismatch",
            "film bindings differ from the plan's")
    require((art["variant"] == "clean-alternate") == plan["cleanAlternate"], "artifactMismatch", "variant differs")
    if art["jobId"] is not None:
        job = jobs.get(art["jobId"])
        require(job is not None and art["artifactId"] in job["deliveredArtifactIds"], "artifactMismatch",
                "the film's job does not list it")
        require(job["planId"] == plan["planId"] and job["planRevision"] == plan["planRevision"], "artifactMismatch",
                "the film's job ran another plan")
        if job["state"] == "ready":
            require(art["verification"]["status"] == "passed", "unverifiedReady", "a ready job's film is verified")
    return plan


def check_jobs(b: dict) -> None:
    """Every delivered artifact a job lists exists and belongs to that job; a ready job lists at least one, and all of
    them passed verification. (The job record alone cannot prove this: an id is not an artifact.)"""
    arts = {a["artifactId"]: a for a in b["artifacts"]}
    for job in b["jobs"].values():
        for aid in job["deliveredArtifactIds"]:
            art = arts.get(aid)
            require(art is not None and art["jobId"] == job["jobId"], "unknownArtifact",
                    f"{job['jobId']} lists {aid}, which is not a delivered artifact of this job")
        if job["state"] == "ready":
            require(job["deliveredArtifactIds"] and all(arts[a]["verification"]["status"] == "passed"
                                                        for a in job["deliveredArtifactIds"]), "unverifiedReady",
                    f"{job['jobId']} is ready only with verified delivered artifacts")


def verified_artifact_for(job: dict, artifacts: list) -> bool:
    """The verified_artifact flag for jobstate replay: resolved from the artifacts, never from the id list alone."""
    arts = {a["artifactId"]: a for a in artifacts}
    ids = job["deliveredArtifactIds"]
    return bool(ids) and all(a in arts and arts[a]["jobId"] == job["jobId"]
                             and arts[a]["verification"]["status"] == "passed" for a in ids)


def check_money(b: dict, plans: list) -> None:
    quotes, reservations, jobs = b["quotes"], b["reservations"], b["jobs"]
    plan_by_key = {(p["planId"], p["planRevision"]): p for p in plans}
    for job in jobs.values():
        if job["reservationId"] is None:
            continue
        res = reservations.get(job["reservationId"])
        require(res is not None and res["jobId"] == job["jobId"], "moneyMismatch", f"{job['jobId']}: reservation missing")
        quote = quotes.get(res["quoteId"])
        require(quote is not None and quote["status"] == "accepted" and not quote["illustrative"]
                and job["quoteId"] == quote["quoteId"], "moneyMismatch", f"{job['jobId']}: no accepted quote")
        plan = plan_by_key.get((job["planId"], job["planRevision"]))
        require(plan is not None, "unknownPlan", f"{job['jobId']}: plan {job['planId']} r{job['planRevision']} missing")
        key = output_spec_hash(plan)
        require(job["idempotencyKey"] == key == res["idempotencyKey"]["outputSpecSha256"] == quote["outputSpecSha256"]
                and res["idempotencyKey"]["planRevision"] == quote["planRevision"] == plan["planRevision"]
                and res["capCredits"] == quote["capCredits"], "moneyMismatch",
                f"{job['jobId']}: job, reservation and quote do not share one key and cap")
        for art in b["artifacts"]:
            if art["jobId"] == job["jobId"]:
                # the film's planner is the one the quote (and its consent) covered: no model-planned film from a
                # rules-planned quote, and no rules film billed as model planning
                require((art["bindings"]["planner"]["kind"] == "model") == (quote["plannerChoice"] == "model"),
                        "plannerMismatch", f"{art['artifactId']}: planner {art['bindings']['planner']['kind']} but "
                        f"quote {quote['quoteId']} is {quote['plannerChoice']}")
        expected_status = {"ready": "settled", "canceled": "canceled", "failed_terminal": "released"}.get(job["state"], "held")
        require(res["status"] == expected_status, "moneyMismatch",
                f"{job['jobId']} is {job['state']} so its reservation is {expected_status}")
        # the entries are tied to this reservation (own key, job, charged stages, status), and every top-up names an
        # accepted quote for the same plan revision and output
        try:
            ledger.check_reservation_record(res)
        except Reject as exc:
            raise Reject("moneyMismatch", f"{res['reservationId']}: {exc.message}") from None
        topups = [e["key"].split(":")[5] for e in res["entries"]
                  if e["kind"] == "reserve" and len(e["key"].split(":")) == 6]
        for qid in [res["initialQuoteId"], *topups[:-1]] if topups else []:
            # every quote a later top-up replaced is superseded: one accepted quote funds one hold, at one time
            old = quotes.get(qid)
            require(old is not None and old["status"] == "superseded", "moneyMismatch",
                    f"{res['reservationId']}: quote {qid} was topped up past, so it is superseded")
        for e in res["entries"]:
            parts = e["key"].split(":")
            if e["kind"] == "reserve" and len(parts) == 6:
                top = quotes.get(parts[5])
                require(top is not None and top["status"] in ("accepted", "superseded") and not top["illustrative"]
                        and top["outputSpecSha256"] == key and top["planRevision"] == plan["planRevision"],
                        "moneyMismatch", f"{res['reservationId']}: top-up {parts[5]} is not an accepted quote for this output")


def check_reference_catalog(b: dict) -> None:
    """The catalog is a projection of stored records: it must agree with them."""
    cat = b["references"]
    current_event = b["keepers"]["eventRevision"]
    require(cat["projectId"] == b["manifest"]["projectId"], "untrustedReference", "catalog of another project")
    require(cat["eventRevision"] == current_event and all(r["eventRevision"] == current_event for r in cat["references"]),
            "staleRevision", "the reference catalog was resolved at an older event revision")
    cues = {c["cueId"]: c for lesson in b["lessons"] for c in lesson["cues"]}
    notes = {n["noteId"]: n for lesson in b["lessons"] for n in lesson["notes"]}
    for r in cat["references"]:
        origin = r["origin"]
        if origin["recordKind"] == "lesson-cue":
            cue = cues.get(origin["recordId"])
            require(cue is not None and r["kind"] == "cue" and cue["provenance"] == r["provenance"], "provenanceMismatch",
                    f"catalog cue {r['refId']} must carry its lesson cue's provenance")
        if origin["recordKind"] == "lesson-note":
            note = notes.get(origin["recordId"])
            require(note is not None and r["kind"] == "note" and note["provenance"] == r["provenance"],
                    "provenanceMismatch", f"catalog note {r['refId']} must carry its lesson note's provenance")
    people = {p["participantId"] for p in b["lock"]["participants"]}
    for c in cat["consents"]:
        require(c["participantId"] in people, "unknownParticipant", f"consent {c['consentRecordId']}: unknown participant")


def check_references(b: dict) -> None:
    keepers = {k["keeperId"] for k in b["keepers"]["keepers"]}
    brolls = {i["brollId"] for i in b["brolls"]["items"]}
    sources = {s["sourceId"] for s in b["manifest"]["sources"]}
    current_event = b["keepers"]["eventRevision"]
    refs = {r["refId"]: r for r in b["references"]["references"]}
    for brief in b["briefs"]:
        require(brief["bindings"]["eventRevision"] == current_event and brief["bindings"]["syncRevision"] == b["syncMap"]["revision"]
                and brief["bindings"]["keeperCatalogRevision"] == b["keepers"]["revision"]
                and brief["bindings"]["brollCatalogRevision"] == b["brolls"]["revision"], "staleRevision",
                f"{brief['briefId']} is bound to older records")
        for beat in brief["beats"]:
            require(beat["keeperId"] is None or beat["keeperId"] in keepers, "untrustedReference", "unknown keeper")
            require(beat["brollId"] is None or beat["brollId"] in brolls, "untrustedReference", "unknown B-roll")
            for o in beat["overlays"]:
                require(o["refId"] in refs and refs[o["refId"]]["kind"] == o["kind"], "untrustedReference",
                        f"{brief['briefId']} beat {beat['beatId']}: overlay {o['refId']} is not a stored {o['kind']}")
            require(beat["noteId"] is None or (beat["noteId"] in refs and refs[beat["noteId"]]["kind"] == "note"),
                    "untrustedReference", f"{brief['briefId']} beat {beat['beatId']}: unknown note")
    observations = {o["observationId"]: o for o in b["observations"]}
    for o in b["observations"]:
        require(o["sourceId"] in sources and o["eventRevision"] == current_event, "untrustedReference",
                f"{o['observationId']}: unknown source or stale event revision")
    for lesson in b["lessons"]:
        for c in lesson["clips"]:
            require(c["keeperId"] is None or c["keeperId"] in keepers, "untrustedReference", "lesson clip keeper")
        for cue in lesson["cues"]:
            if cue["observationId"] is not None:
                obs = observations.get(cue["observationId"])
                require(obs is not None and obs["provenance"]["status"] == cue["provenance"], "provenanceMismatch",
                        f"cue {cue['cueId']} must carry its observation's provenance")


def check_all(b: dict) -> dict:
    """Run every cross-record rule; returns counts for the report."""
    check_lock(b)
    check_sync_against_manifest(b)
    check_catalogs(b)
    for plan in b["plans"]:
        check_plan_against_trusted(plan, b)
    by_id = {p["planId"]: p for p in b["plans"]}
    pairs = 0
    for plan in b["plans"]:
        if plan["cleanAlternate"]:
            base = by_id.get(plan["planId"][: -len("-clean")])
            require(base is not None and plan["planId"].endswith("-clean"), "cleanAlternateMismatch",
                    f"{plan['planId']} has no primary plan")
            check_clean_pair(base, plan)
            pairs += 1
    for art in b["artifacts"]:
        check_artifact_against_plan(art, b["plans"], b["jobs"])
    check_jobs(b)
    check_money(b, b["plans"])
    check_reference_catalog(b)
    check_references(b)
    return {"plans": len(b["plans"]), "cleanPairs": pairs, "artifacts": len(b["artifacts"]), "jobs": len(b["jobs"])}


def expect_reject(fn, code: str) -> None:
    try:
        fn()
    except Reject as exc:
        require(exc.code == code, "selfTestMismatch", f"expected {code}, got {exc.code}: {exc.message}")
        return
    raise Reject("selfTestMismatch", f"a mutation that should fail with {code} was accepted")
