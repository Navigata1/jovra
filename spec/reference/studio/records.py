"""Semantic rules for Studio records that a JSON Schema cannot express. Each check raises Reject(code, message).

Cross-record rules (an EDL against its SyncMap, keepers and manifest; a film against its plan) live in
scripts/spec/validate_studio.py, which assembles a project's records first.
"""

from __future__ import annotations

from datetime import timedelta

from .core import Reject, canonical_sha256, delta_pp_display, pct, require, when
from .syncfit import check_review_state, fit_device, map_us, speed_of_sound_mm_per_s

INVITE_MAX_LIFETIME = timedelta(minutes=10)
SHARE_LINK_MAX_LIFETIME = timedelta(hours=24)
CAMERA_PERMISSIONS = {"record-local", "upload-own-source", "view-own-preview"}


def unique(values, code: str, what: str) -> None:
    values = list(values)
    require(len(values) == len(set(values)), code, f"duplicate {what}")


# ----- ProjectLock --------------------------------------------------------------------------------

def check_project_lock(doc: dict) -> None:
    if doc["environment"] == "demo":
        require(doc["identity"]["mode"] == "demo-profile" and doc["identity"]["accountRef"] is None, "demoIdentity",
                "the local demo uses the demo profile and no account")
        require(doc["quoteAuthorization"] is None, "demoNeverReserves", "a demo project has no quote authorization")
        require(all(not r["cloudConsent"] for r in doc["sourceRights"]), "demoNoUpload", "the demo never uploads")
    else:
        require(doc["identity"]["mode"] != "demo-profile", "demoIdentity", "demo identities are refused outside demo")
    people = {p["participantId"]: p for p in doc["participants"]}
    unique(people, "duplicateId", "participant")
    for right in doc["sourceRights"]:
        require(right["ownerParticipantId"] in people, "unknownParticipant", "source owner is not a participant")
        if right["cloudConsent"]:
            require(right["consentRecordId"] is not None, "consentMissing", "cloud consent needs a consent record")
            require(people[right["ownerParticipantId"]]["recordingAcknowledged"], "consentMissing",
                    "the owner acknowledged recording before consenting to upload")
    if doc["privacy"]["locationHidden"]:
        require(not doc["privacy"]["venueVisible"], "privacyConflict", "a hidden location cannot show the venue")


# ----- SourceManifest -----------------------------------------------------------------------------

def check_source_manifest(doc: dict) -> None:
    sources = doc["sources"]
    unique((s["sourceId"] for s in sources), "duplicateId", "source")
    match = [s for s in sources if s["role"] == "match"]
    require(1 <= len(match) <= 6, "badSources", "one to six match sources")
    require(sum(1 for s in match if s["isPrimary"]) == 1 and not any(s["isPrimary"] for s in sources
                                                                      if s["role"] == "broll"),
            "primaryCount", "exactly one primary match source")
    slots = [s["slot"] for s in match if s["slot"] != "custom"]
    unique(slots, "slotTaken", "placement slot")
    for s in sources:
        o = s["original"]
        if s["role"] == "match":
            require(s["slot"] is not None, "badSlot", "a match source has a placement slot")
        if s["isPrimary"]:
            require(s["slot"] in ("near-baseline", "custom"), "badSlot", "the primary is the near-baseline angle")
        require(not o["colour"]["hdr"] or o["colour"]["transfer"] in ("hlg", "pq"), "colourMismatch",
                "HDR sources declare an HLG or PQ transfer")
        require(o["startPts"]["timescale"] == o["timescale"], "badTimebase", "startPts uses the track timescale")
        segs = s["segments"]
        require([g["index"] for g in segs] == list(range(len(segs))), "badSegments", "segment indexes run 0..n-1")
        unique((g["segmentId"] for g in segs), "duplicateId", "segment")
        require(sum(g["durationUs"] for g in segs) <= o["durationUs"], "badSegments",
                "segments cannot last longer than the original")
        require(sum(g["frameCount"] for g in segs) == o["frameCount"], "badSegments",
                "segment frame counts add up to the original's")
        require(segs[0]["reason"] in ("start", "import"), "badSegments", "the first segment starts or is imported")
        hosts = [g["fileZeroHostNs"] for g in segs if g["fileZeroHostNs"] is not None]
        require(hosts == sorted(hosts), "badSegments", "journalled host times increase across restarts")
        quarter_turn = o["video"]["rotationDegrees"] in (90, 270)
        for p in s["proxies"]:
            if p["class"] == "render":
                require(p["rotationApplied"] == (o["video"]["rotationDegrees"] != 0), "proxyRotation",
                        "a render proxy bakes the rotation in exactly once")
                require(p["toneMapped"] == o["colour"]["hdr"], "proxyColour", "a render proxy of HDR is tone-mapped SDR")
                if quarter_turn:
                    require((p["width"] > p["height"]) != (o["video"]["width"] > o["video"]["height"]),
                            "proxyRotation", "a quarter-turn render proxy swaps width and height")
        if s["verification"]["status"] == "verified":
            require(s["verification"]["method"] is not None and s["verification"]["verifiedAt"] is not None,
                    "badVerification", "verified needs the method and time")


# ----- SyncMap ------------------------------------------------------------------------------------

def check_sync_map(doc: dict, hints: dict | None = None) -> dict:
    """Refits every non-reference device and requires the stored numbers to equal the reference fitter's.

    hints: {sourceId: {segmentId: offsetUs}} capture hints derived from the SourceManifest (bundle.capture_hints).
    Without them no piece can be from-hints. A piece has matchCoverage exactly when it has a transform. On the
    reference device only referenceSegmentId is 'reference' (rate 1); a restarted segment of the reference device is
    placed from its own capture journal (from-hints, rate 1, offset = the journal hint) or is failed with no transform:
    its offset is derived, never invented, and from-hints is never cut or reviewed."""
    hints = hints or {}
    c = doc["speedOfSound"]
    if doc["speedOfSound"]["method"] == "default-343":
        require(c["temperatureC"] is None and c["mmPerSecond"] == 343_000, "badSpeedOfSound", "default is 343 m/s")
    else:
        require(c["mmPerSecond"] == speed_of_sound_mm_per_s(c["temperatureC"]), "badSpeedOfSound",
                "mmPerSecond must equal c(T)")
    positions = {p["sourceId"]: p["positionMm"] for p in doc["placements"]}
    ref_id = doc["matchClock"]["referenceSourceId"]
    require(ref_id in positions, "unknownSource", "the reference source needs a placement")
    unique((s["sourceId"] for s in doc["sources"]), "duplicateId", "source map")
    starts = []
    fitted_states = []
    for smap in doc["sources"]:
        sid = smap["sourceId"]
        require(sid in positions, "unknownSource", f"{sid} has no placement")
        for piece in smap["pieces"]:
            require((piece["matchCoverage"] is None) == (piece["transform"] is None), "badCoverage",
                    f"{sid}/{piece['segmentId']}: matchCoverage exists exactly when a transform does")
        if sid == ref_id:
            rate1 = {"num": 1_000_000_000, "den": 1_000_000_000}
            for piece in smap["pieces"]:
                require(piece["anchors"] == [] and piece["fit"] is None, "badReference",
                        "reference-device pieces carry no anchors or fit")
                if piece["segmentId"] == doc["matchClock"]["referenceSegmentId"]:
                    require(piece["state"] == "reference" and piece["transform"] is not None
                            and piece["transform"]["rate"] == rate1, "badReference",
                            "the reference segment is state reference and runs at rate 1")
                else:
                    hint = hints.get(sid, {}).get(piece["segmentId"])
                    if hint is None:
                        require(piece["state"] == "failed" and piece["transform"] is None, "badReference",
                                f"{sid}/{piece['segmentId']}: a restarted reference segment with no capture journal "
                                "has no transform (failed)")
                    else:
                        require(piece["state"] == "from-hints" and piece["transform"] == {"offsetUs": hint, "rate": rate1},
                                "badReference",
                                f"{sid}/{piece['segmentId']}: a restarted reference segment is placed from its capture "
                                f"journal (from-hints, offset {hint}, rate 1), never from an invented offset or rate")
                if piece["transform"] is not None:
                    _coverage(piece)
                    starts.append(piece["matchCoverage"]["startUs"])
            _gaps(smap)
            continue
        pieces = [{"segmentId": p["segmentId"], "sourceDurationUs": p["sourceDurationUs"],
                   "anchors": [{k: a[k] for k in ("id", "kind", "modality", "sourceTimeUs", "referenceTimeUs",
                                                  "eventPositionMm")} for a in p["anchors"]]} for p in smap["pieces"]]
        fitted = fit_device(pieces, source_position=positions[sid], reference_position=positions[ref_id],
                            c_mm_per_s=c["mmPerSecond"], output_fps=doc["outputFps"], hints=hints.get(sid))
        for stored, got in zip(smap["pieces"], fitted):
            where = f"{sid}/{stored['segmentId']}"
            require(stored["transform"] == got["transform"], "syncFitMismatch",
                    f"{where}: stored transform {stored['transform']} != fitted {got['transform']}")
            require(stored["fit"] == got["fit"], "syncFitMismatch", f"{where}: stored fit statistics differ")
            for a, g in zip(stored["anchors"], got["anchors"]):
                for key in ("sourceDelayUs", "referenceDelayUs", "corrected", "residualUs", "inlier"):
                    require(a[key] == g[key], "syncFitMismatch", f"{where} anchor {a['id']}: {key} {a[key]} != {g[key]}")
            check_review_state(stored["state"], got["state"], stored["checkpoints"], got["fit"])
            if stored["state"] == "reviewed":
                require(stored["reviewedAt"] is not None, "reviewIncomplete", "reviewed needs reviewedAt")
            if stored["state"] in ("estimated", "needs-review"):
                require(stored["reasons"] == got["reasons"], "syncFitMismatch", f"{where}: reasons differ")
            if stored["transform"] is not None:
                _coverage(stored)
                starts.append(stored["matchCoverage"]["startUs"])
            fitted_states.append(stored["state"])
        _gaps(smap)
    require(min(starts) == 0, "badOrigin", "the match clock starts at the earliest covered instant")
    status = doc["provenance"]["status"]
    if fitted_states and all(s == "reviewed" for s in fitted_states):
        require(status == "reviewed", "badProvenance", "all maps reviewed -> provenance reviewed")
    elif fitted_states and all(s == "manual" for s in fitted_states):
        require(status == "manual", "badProvenance", "marker-only maps are manual")
    else:
        require(status == "estimated", "badProvenance", "unreviewed maps are estimated")
    return {"states": fitted_states}


def _coverage(piece: dict) -> None:
    t = piece["transform"]
    require(t is not None and piece["matchCoverage"] is not None, "badCoverage", "a mapped piece has coverage")
    expect = {"startUs": map_us(t, 0), "endUs": map_us(t, piece["sourceDurationUs"])}
    require(piece["matchCoverage"] == expect, "badCoverage",
            f"{piece['segmentId']}: matchCoverage must be {expect} from its transform")


def _gaps(smap: dict) -> None:
    covered = sorted((p["matchCoverage"]["startUs"], p["matchCoverage"]["endUs"]) for p in smap["pieces"]
                     if p["matchCoverage"] is not None)
    for (a0, a1), (b0, b1) in zip(covered, covered[1:]):
        require(a1 <= b0, "overlappingPieces", "pieces of one device cannot overlap on the match clock")
    expected = [(a1, b0) for (a0, a1), (b0, b1) in zip(covered, covered[1:]) if a1 < b0]
    got = [(g["match"]["startUs"], g["match"]["endUs"]) for g in smap["gaps"]]
    require(got == expected, "badGaps", f"gaps must be exactly the uncovered spans between pieces {expected}")


# ----- Observation ----------------------------------------------------------------------------------

def check_observation(doc: dict) -> None:
    p = doc["provenance"]
    require(doc["sourceTime"]["startUs"] <= doc["sourceTime"]["endUs"], "badInterval", "source time interval")
    if p["status"] == "manual":
        require(p["producer"] in ("user", "coach") and p["confidence"] is None and doc["capabilityId"] is None,
                "provenanceMismatch", "manual observations come from a person, with no model confidence")
    if p["status"] == "estimated":
        require(p["producer"].startswith(("model:", "rule:")) and p["confidence"] is not None
                and doc["capabilityId"] is not None and doc["capabilityVersion"] is not None, "provenanceMismatch",
                "estimated observations name their capability, producer and confidence")
    if p["status"] == "reviewed":
        require(doc["reviewedBy"] is not None, "provenanceMismatch", "reviewed names the reviewer")
    if p["status"] == "validated":
        require(p["benchmarkRef"] is not None, "provenanceMismatch", "validated needs the capability's benchmark")
    if p["calibrationRequired"]:
        require(p["calibrationId"] is not None, "calibrationMissing",
                "this capability depends on a court calibration; without one it is unsupported, not estimated")
    if doc["sessionTimeUs"] is not None:
        require(doc["syncRevision"] is not None, "badSessionTime", "session time needs the sync revision it came from")
    if doc["status"] == "accepted" and p["status"] == "estimated":
        raise Reject("provenanceMismatch", "accepting an estimated observation makes it reviewed")


# ----- Keepers and B-roll -------------------------------------------------------------------------

def check_keeper_catalog(doc: dict) -> None:
    unique((k["keeperId"] for k in doc["keepers"]), "duplicateId", "keeper")
    events = [e for k in doc["keepers"] for e in k["eventRefs"]]
    unique(events, "duplicateEvent", "point event across keepers (a second angle is a view, not another event)")
    for k in doc["keepers"]:
        require(k["session"]["startUs"] < k["session"]["endUs"], "badInterval", "keeper session interval")
        views = {v["sourceId"]: v for v in k["views"]}
        require(len(views) == len(k["views"]), "duplicateId", "one view per source")
        require(sum(1 for v in k["views"] if v["primary"]) == 1, "primaryCount", "exactly one primary view")
        for v in k["views"]:
            require(v["window"]["inFrame"] < v["window"]["outFrame"], "badInterval", "view window")
        for c in k["contacts"]:
            v = views.get(c["sourceId"])
            require(v is not None and v["window"]["inFrame"] <= c["frame"] < v["window"]["outFrame"], "badContact",
                    "a contact lies inside a view of the same source")


def check_broll_catalog(doc: dict) -> None:
    unique((i["brollId"] for i in doc["items"]), "duplicateId", "B-roll item")
    for i in doc["items"]:
        require(i["window"]["inFrame"] < i["window"]["outFrame"], "badInterval", "B-roll window")
        if i["origin"] in ("stock", "generated", "captured-other-day"):
            require(not i["depictsThisMatch"], "brollMisrepresented", "only today's footage depicts this match")
        if i["origin"] in ("stock", "generated"):
            require(i["disclosureTemplateId"] == "label.not-match-footage" and i["rights"]["rightsRecordId"],
                    "brollMisrepresented", "stock or generated material is labelled and has a rights record")
        if i["rights"]["holder"] == "licensor":
            require(i["rights"]["rightsRecordId"] is not None, "rightsMissing", "licensed material needs its record")


# ----- Story profiles and briefs ------------------------------------------------------------------

def check_profile_catalog(doc: dict) -> dict:
    by_id = {p["id"]: p for p in doc["profiles"]}
    require(len(by_id) == 5, "duplicateId", "five distinct profiles")
    for p in doc["profiles"]:
        g = p["grammar"]
        lo, hi = p["recommendedDurationSeconds"]
        require(g["durationSeconds"] == {"min": lo, "max": hi}, "profileMismatch",
                f"{p['id']}: grammar duration must equal the recommended range")
        for rng in ("freezeMs", "cardMs", "durationSeconds"):
            require(g[rng]["min"] <= g[rng]["max"], "badRange", f"{p['id']}: {rng}")
        require(("replay" in g["ops"]) == bool(g["replaySpeedDens"]), "profileMismatch",
                f"{p['id']}: replay speeds exist exactly when replays are allowed")
        require(not g["transitions"] or g["maxTransitionMs"] > 0, "profileMismatch", "transition length")
        require("cue" not in g["overlays"] or "estimated" not in g["overlays"]["cue"], "profileMismatch",
                "an estimated cue is never shown as instruction")
        # spec D-1 / SD5: exports default to no audio (core D5) except Rally Pulse and Court Memories
        require(p["exportAudio"]["includeByDefault"] == (p["id"] in ("rally-pulse", "court-memories")),
                "profileMismatch", f"{p['id']}: Include audio starts on only for Rally Pulse and Court Memories (D-1)")
    return by_id


def comparison_display(c: dict) -> dict:
    b, a = c["before"], c["after"]
    pb, pa = pct(b["numerator"], b["denominator"]), pct(a["numerator"], a["denominator"])

    def side(s, p):
        shown = "—" if p is None else f"{p}%"
        return f"{s['numerator']} / {s['denominator']} · {shown}"
    return {"before": side(b, pb), "after": side(a, pa),
            "delta": delta_pp_display(pb, pa) if c["claim"] == "change" else "—"}


def check_story_brief(doc: dict, profiles: dict) -> None:
    profile = profiles.get(doc["profile"]["id"])
    require(profile is not None and profile["revision"] == doc["profile"]["revision"], "staleRevision",
            "brief bound to an unknown or older profile revision")
    g = profile["grammar"]
    unique((b["beatId"] for b in doc["beats"]), "duplicateId", "beat")
    for b in doc["beats"]:
        t = b["treatment"]
        require(t in g["ops"], "opNotAllowed", f"{t} is not used in {profile['id']}")
        if t in ("live", "replay", "freeze"):
            require(b["keeperId"] is not None, "beatWithoutEvidence", f"beat {b['beatId']} needs a keeper")
        if t == "broll":
            require(b["brollId"] is not None, "beatWithoutEvidence", f"beat {b['beatId']} needs a B-roll item")
        if t == "title-card":
            require(b["templateId"] is not None and b["templateId"].startswith("card."), "beatWithoutEvidence",
                    f"card beat {b['beatId']} needs a catalog card template")
        require((t == "replay") == (b["replaySpeedDen"] is not None), "badReplay", "replay speed only on replays")
        if t == "replay":
            require(b["replaySpeedDen"] in g["replaySpeedDens"], "badSpeed", "replay speed not allowed")
        for o in b["overlays"]:
            require(o["kind"] in g["overlays"], "overlayNotAllowed", f"{o['kind']} overlay not used in this profile")
    if doc["music"] is not None:
        require(g["music"], "opNotAllowed", "music is not used in this profile")
    if doc["narration"] is not None:
        require(g["narration"], "opNotAllowed", "narration is not used in this profile")
    lo, hi = g["durationSeconds"]["min"], g["durationSeconds"]["max"]
    require(lo <= doc["durationTargetSeconds"] <= hi, "durationOutsideProfile", "target outside the profile range")
    for c in doc["comparisons"]:
        if c["claim"] == "change":
            require(c["before"]["provenance"] in ("reviewed", "validated")
                    and c["after"]["provenance"] in ("reviewed", "validated"), "weakEvidence",
                    "a change claim needs reviewed evidence on both sides")
            require(c["selectionRule"] != "user-chosen", "selectionBias",
                    "user-chosen examples cannot carry a change claim")
        require(c["before"]["date"] < c["after"]["date"], "badComparison", "before is earlier than after")
        require(c["display"] == comparison_display(c), "displayMismatch",
                f"display must be {comparison_display(c)} (integer pct, percentage points)")


# ----- Quote, artifact, lesson, invites, providers -----------------------------------------------

def check_quote(doc: dict, classes: dict) -> None:
    from .ledger import quote_credits
    require(when(doc["expiresAt"]) - when(doc["createdAt"]) <= timedelta(seconds=classes["quoteMaxLifetimeSeconds"]),
            "quoteLifetime", "a quote expires within 30 minutes")
    require(when(doc["createdAt"]) < when(doc["expiresAt"]), "quoteLifetime", "expiry after creation")
    require(doc["capCredits"] == quote_credits(classes, doc["filmClass"], doc["estimatedMaxCostMicroUsd"]),
            "quoteCapMismatch", "cap must follow the class minimum and the cost estimate")
    require(doc["estimate"]["minCredits"] <= doc["estimate"]["maxCredits"] <= doc["capCredits"], "badQuote",
            "estimate min <= max <= cap")
    if doc["illustrative"]:
        require(doc["sample"] and doc["status"] != "accepted" and doc["consent"] is None, "illustrativeQuote",
                "an illustrative quote is Sample, never accepted and never consented")
    if doc["displayAmounts"] is not None:
        d = doc["displayAmounts"]
        require(doc["illustrative"], "illustrativeQuote", "money amounts are shown only as illustrative Sample UX")
        require(d["minMinor"] <= d["maxMinor"] <= d["capMinor"], "badQuote", "display min <= max <= cap")
    if doc["status"] == "accepted":
        require(doc["acceptedAt"] is not None and doc["consent"] is not None, "consentMissing",
                "an accepted quote records the owner's upload consent")
        require(when(doc["acceptedAt"]) < when(doc["expiresAt"]) and when(doc["consent"]["at"]) <= when(doc["acceptedAt"]),
                "quoteExpired",
                "a quote is accepted, after consent, before it expires; never auto-accepted later")
    else:
        require(doc["acceptedAt"] is None, "badQuote", "only accepted quotes have acceptedAt")
    if doc["environment"] != "live":
        require(doc["sample"], "sampleRequired", "demo and test quotes are Sample")
    require(doc["lineItems"]["storageDays"] == doc["retentionDays"], "badQuote",
            "the storage line item is priced for the chosen retention")
    if doc["plannerChoice"] == "heuristic":
        require(doc["lineItems"]["plannerTokensEstimate"] == 0, "plannerMismatch",
                "a rules-planned quote estimates no model tokens")
    consent = doc["consent"]
    if consent is not None:
        require(consent["retentionDays"] == doc["retentionDays"], "badQuote",
                "the consent confirms the quote's retention")
        require(consent["modelProvider"] == (doc["plannerChoice"] == "model"), "consentMissing",
                "model planning needs the explicit model-provider consent, and a rules-planned quote records none")
        require(consent["modelProvider"] or consent["textClasses"] == [], "badQuote",
                "note text classes are consented only together with model planning")


def check_artifact(doc: dict) -> None:
    m = doc["media"]
    if doc["chapters"]:
        require(doc["chapters"][0]["startFrame"] == 0 and doc["chapters"][-1]["endFrame"] == m["durationFrames"],
                "badChapters", "chapters cover the whole film")
        for a, b in zip(doc["chapters"], doc["chapters"][1:]):
            require(a["endFrame"] == b["startFrame"], "badChapters", "chapters are contiguous")
        for c in doc["chapters"]:
            require(c["startFrame"] < c["endFrame"], "badChapters", "empty chapter")
    v = doc["verification"]
    checks = [v[k] for k in ("probe", "fullDecode", "frameCount", "audio", "overlayProvenance")]
    if v["status"] == "passed":
        require(all(c in ("passed", "not-applicable") for c in checks) and v["fullDecode"] == "passed"
                and v["frameCount"] == "passed" and v["checkedAt"] is not None, "unverifiedReady",
                "passed means probe, full decode, frame count, audio and overlay checks all passed")
    if v["status"] == "failed":
        require(any(c == "failed" for c in checks), "badVerification", "a failed verification names the failing check")
    if m["audioCodec"] is None:
        require(m["audioSampleCount"] is None and v["audio"] == "not-applicable", "badAudio", "no audio track")
    else:
        require(v["audio"] != "not-applicable", "badAudio", "an audio track is verified")
    link = doc["delivery"]["shareLink"]
    if link is not None:
        require(v["status"] == "passed", "unverifiedShare", "only verified films can be shared")
        span = when(link["expiresAt"]) - when(link["issuedAt"])
        require(timedelta(0) < span <= SHARE_LINK_MAX_LIFETIME, "shareLinkLifetime", "share links expire within 24 h")
    r = doc["delivery"]["retention"]
    require((r["policy"] == "days") == (r["days"] is not None), "badRetention", "days only with the days policy")
    if doc["environment"] == "demo":
        require(r["policy"] == "device-only" and link is None, "demoNoUpload", "demo films stay on the device")
    if doc["youtubePrep"]["prepared"]:
        require(v["status"] == "passed", "unverifiedShare", "prepare for YouTube only after verification")


def check_lesson(doc: dict) -> None:
    clips = {c["clipId"]: c for c in doc["clips"]}
    unique(clips, "duplicateId", "clip")
    unique((n["noteId"] for n in doc["notes"]), "duplicateId", "note")
    unique((c["cueId"] for c in doc["cues"]), "duplicateId", "cue")
    unique((i["itemId"] for i in doc["practice"]), "duplicateId", "practice item")
    for n in doc["notes"]:
        require(all(c in clips for c in n["clipIds"]), "unknownClip", "a note links only this lesson's clips")
        if n["author"] == "coach":
            require(doc["coach"] is not None, "unattributedCoach", "a coach note needs the lesson's coach")
    for c in doc["clips"]:
        require(c["sourceId"] is not None or c["sessionId"] is not None, "clipWithoutSource",
                "a clip points at a source or session")
        if c["window"] is not None:
            require(c["window"]["startUs"] < c["window"]["endUs"], "badInterval", "clip window")
    for cue in doc["cues"]:
        require(cue["clipId"] in clips, "unknownClip", "a cue is anchored to one of this lesson's clips")
        if cue["provenance"] == "estimated":
            require(cue["observationId"] is not None and cue["reviewedBy"] is None, "provenanceMismatch",
                    "an estimated cue comes from an observation and is not reviewed")
        if cue["provenance"] == "reviewed":
            require(cue["reviewedBy"] is not None, "provenanceMismatch", "a reviewed cue names its reviewer")
    for item in doc["practice"]:
        require(item["done"] <= item["target"], "badPractice", "done cannot exceed the target")
        expected = "done" if item["done"] == item["target"] else ("pending" if item["done"] == 0 else "in-progress")
        require(item["status"] == expected, "badPractice", f"{item['itemId']}: status must be {expected}")
    if doc["share"]["mode"] == "private":
        require(doc["share"]["grantIds"] == [], "badShare", "a private lesson has no grants")


def check_camera_invites(doc: dict) -> None:
    roles = doc["roles"]
    require(sum(1 for r in roles if r["role"] == "primary") == 1, "primaryCount", "exactly one primary camera")
    unique((r["slot"] for r in roles), "slotTaken", "slot")
    for r in roles:
        if r["role"] == "primary":
            require(r["slot"] == "near-baseline", "badSlot", "the primary is the near-baseline camera")
        else:
            require(set(r["permissions"]) <= CAMERA_PERMISSIONS, "permissionEscalation",
                    "a camera records locally and uploads only its own source")
        if r["status"] == "ready":
            require(r["recordingAcknowledged"] and r["deviceId"] is not None, "notReady",
                    "ready means a device joined and acknowledged recording")
    filled = {r["slot"] for r in roles if r["deviceId"] is not None}
    unique((i["inviteId"] for i in doc["invites"]), "duplicateId", "invite")
    for i in doc["invites"]:
        span = when(i["expiresAt"]) - when(i["issuedAt"])
        require(timedelta(0) < span <= INVITE_MAX_LIFETIME, "inviteLifetime", "invites expire within 10 minutes")
        if i["status"] == "accepted":
            require(i["acceptedAt"] is not None and i["deviceId"] is not None and when(i["acceptedAt"]) < when(i["expiresAt"]),
                    "inviteExpired", "an invite is accepted by one device before it expires")
            require(i["slot"] in filled, "badInvite", "an accepted invite fills its slot")
        else:
            require(i["acceptedAt"] is None and i["deviceId"] is None, "badInvite", "only accepted invites bind a device")
            if i["status"] == "issued":
                require(i["slot"] not in filled, "slotTaken", "an open invite cannot target a filled slot")
    if doc["environment"] == "demo":
        require(all(i["status"] != "accepted" for i in doc["invites"]), "demoNoNetwork",
                "the local demo has no network, so no invite is ever accepted")


def check_storage_providers(doc: dict) -> None:
    unique((p["provider"] for p in doc["providers"]), "duplicateId", "provider")
    for p in doc["providers"]:
        ops = p["operations"]
        if p["status"] in ("planned", "not-connected", "unavailable", "disconnected", "token-expired"):
            require(not any(ops.values()), "capabilityOverclaim", f"{p['provider']} is {p['status']}: no operations")
        if p["status"] in ("planned", "not-connected", "unavailable", "disconnected"):
            require(p["credentialRef"] is None, "capabilityOverclaim", "no credential for an unconnected provider")
        if p["provider"] == "device":
            require(p["integration"] == "local" and p["status"] == "active", "badProvider", "the device is local")
        if p["provider"] == "icloud-drive-files":
            require(p["integration"] == "files-picker" and not p["platforms"]["android"], "badProvider",
                    "iCloud Drive is reached through the iOS Files picker, not on Android")
            require(not ops["quota"], "capabilityOverclaim", "the Files picker exposes no quota")
        if p["provider"] in ("google-drive", "box", "dropbox"):
            if p["status"] == "active":
                require(p["integration"] == "oauth-verified" and p["credentialRef"] is not None, "capabilityOverclaim",
                        "an OAuth provider is active only once its integration is verified and connected")
            if p["status"] == "planned":
                require(p["integration"] == "oauth-planned", "capabilityOverclaim", "planned integrations say so")
        if p["status"] == "choose-folder":
            require(p["folderRef"] is None, "badProvider", "no folder chosen yet")
    if doc["environment"] == "demo":
        require(all(p["credentialRef"] is None for p in doc["providers"]), "demoNoTokens", "the demo holds no tokens")


def check_reference_catalog(doc: dict) -> None:
    unique((r["refId"] for r in doc["references"]), "duplicateId", "reference")
    unique((c["consentRecordId"] for c in doc["consents"]), "duplicateId", "consent")
    unique((r["rightsRecordId"] for r in doc["rights"]), "duplicateId", "rights record")
    for r in doc["references"]:
        require(r["eventRevision"] == doc["eventRevision"], "staleRevision",
                f"{r['refId']} was resolved at another event revision than the catalog's")
        kind_by_origin = {"point-event": "score", "score-state": "score", "stat": "metric", "user-note": "note",
                          "lesson-note": "note", "lesson-cue": "cue", "annotation": "annotation"}
        require(kind_by_origin[r["origin"]["recordKind"]] == r["kind"], "kindMismatch",
                f"{r['refId']}: a {r['origin']['recordKind']} is never a {r['kind']}")


def lock_manifest_hash(manifest: dict) -> str:
    return canonical_sha256(manifest)
