"""Synthetic multi-angle fixtures (S58): the ground truth under spec/studio/fixtures/media/multiangle/. Module page:
spec/studio/modules/multiangle-generator.md.

The media is generated at test time by scripts/media/studio/multiangle/generate.py; only the ground truth is
committed. ``fixtures`` declares every file so the fixture generator keeps it and the determinism pass checks it: the
plan part is recomputed from the generator (no pixel drawn, no ffmpeg), and ``hashes`` is carried over from the
committed file (what only a render proves).

The self-tests read the committed documents only and check them against rules written independently of the
generator: every segment's frame-time hash re-derived from its own transform and frame timing; coverage, gaps, the
journal's single host map, the reference's identity piece; each arrival re-derived from the event position, the
placement and syncfit's sound delay; each visible event's frame; shared coverage; the shake marks; and the rig's
tables against the research 4.4 numbers the sound-delay vectors carry.
"""

from __future__ import annotations

import hashlib
import json
import sys
from fractions import Fraction
from itertools import combinations
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
MULTIANGLE = ROOT / "scripts" / "media" / "studio" / "multiangle"
FIX = ROOT / "spec" / "studio" / "fixtures"
for _p in (MULTIANGLE, MULTIANGLE.parent, MULTIANGLE.parents[1], ROOT / "spec" / "reference"):
    if str(_p) not in sys.path:
        sys.path.insert(0, str(_p))

from jovra_multiangle import truth  # noqa: E402
from studio import syncfit  # noqa: E402

SCHEMAS = {truth.RIG_SCHEMA: "studio-multiangle-rig.schema.json", truth.SCHEMA: "studio-multiangle-truth.schema.json"}
RIG = f"{truth.FIXTURES}/rig.json"
US = 1_000_000
GAP_US = 41_000_000           # the ticket's restart gap
TICKET_PROFILES = {"drift-default", "drift-stress-300ppm", "restart-41s-journal", "restart-41s-no-journal",
                   "late-start", "shake", "muted", "mixed-fps", "vfr-rotated-hdr", "no-shared-coverage",
                   "opposite-baseline-audio-only"}


def _committed_hashes(rel: str) -> dict | None:
    path = FIX / rel
    if not path.is_file():
        return None
    return json.loads(path.read_text(encoding="utf-8")).get("hashes")


def fixtures(sample) -> dict:
    src_hash = truth.source_hash()
    docs = {RIG: truth.rig()}
    for pid in truth.profile_ids():
        rel = f"{truth.FIXTURES}/{pid}.json"
        docs[rel] = truth.document(truth.profile_plan(pid, src_hash), _committed_hashes(rel))
    return docs


# ----- independent rules -------------------------------------------------------------------------

def _q(d: dict) -> Fraction:
    return Fraction(d["num"], d["den"])


def _half_up(v: Fraction) -> int:
    return (v + Fraction(1, 2)).__floor__()


def _source_us(cam: dict, n: int) -> Fraction:
    timing = cam["frameTiming"]
    if timing["kind"] == "cfr":
        return Fraction(n * US * cam["frameRate"]["den"], cam["frameRate"]["num"])
    cycle = timing["cycle"]
    return Fraction(((n // len(cycle)) * sum(cycle) + sum(cycle[: n % len(cycle)])) * US, timing["timescale"])


def _match(seg: dict, source: Fraction) -> Fraction:
    return _q(seg["transform"]["offsetUs"]) + _q(seg["transform"]["rate"]) * source


def _coverage(cam: dict, seg: dict) -> tuple[Fraction, Fraction]:
    return _match(seg, Fraction(0)), _match(seg, _q(seg["sourceDurationUs"]))


def _profiles() -> list[tuple[str, dict]]:
    return [(p.relative_to(FIX).as_posix(), json.loads(p.read_text(encoding="utf-8")))
            for p in sorted((FIX / truth.FIXTURES).glob("*.json")) if p.name != "rig.json"]


def _camera_problems(doc: dict, cam: dict, light: dict, positions: dict) -> list[str]:
    out = []
    where = cam["cameraId"]
    rate = _q(cam["clock"]["rate"])
    if rate != Fraction(10**9 + cam["clock"]["driftPpb"], 10**9):
        out.append(f"{where}: clock rate is not 1 + driftPpb / 1e9")
    if cam["reference"] and (rate != 1 or len(cam["segments"]) != 1
                             or _q(cam["segments"][0]["transform"]["offsetUs"]) != 0):
        out.append(f"{where}: the reference camera must be the identity piece")
    if cam["positionMm"] != next(p["positionMm"] for p in json.loads((FIX / RIG).read_text())["placements"]
                                 if p["code"] == cam["placement"]):
        out.append(f"{where}: position is not its rig placement")
    covs = []
    for seg in cam["segments"]:
        if _q(seg["transform"]["rate"]) != rate:
            out.append(f"{where}: segment {seg['segment']} does not share the device rate")
        fps = Fraction(cam["frameRate"]["num"], cam["frameRate"]["den"])
        if _q(seg["sourceDurationUs"]) != seg["frameCount"] * US / fps:
            out.append(f"{where}: segment {seg['segment']} duration is not frameCount / fps")
        # One host map: a_k = hostOffset + rate * h_k, whether or not a journal recorded h_k.
        if _q(seg["transform"]["offsetUs"]) != cam["clock"]["hostOffsetUs"] + rate * seg["hostStartUs"]:
            out.append(f"{where}: segment {seg['segment']} offset does not follow the host clock")
        sha = hashlib.sha256()
        for n in range(seg["frameCount"]):
            sha.update(_half_up(_match(seg, _source_us(cam, n))).to_bytes(8, "big", signed=True))
        if sha.hexdigest() != seg["frameTimesSha256"]:
            out.append(f"{where}: segment {seg['segment']} frameTimesSha256 is not its transform over its frames")
        start, end = _coverage(cam, seg)
        covs.append((start, end))
        if seg["matchCoverageUs"] != {"startUs": _half_up(start), "endUs": _half_up(end)}:
            out.append(f"{where}: segment {seg['segment']} coverage is not its transform over the file")
        heard = sorted(a["sourceSample"] for a in cam["audioArrivals"] if a["heard"] and a["segment"] == seg["segment"])
        for f in seg["files"]:
            if f["clickSamples"] != heard:
                out.append(f"{where}: {f['fileName']} clicks are not the heard arrivals")
            if f["audioSampleCount"] * US != _q(seg["sourceDurationUs"]) * 48_000:
                out.append(f"{where}: {f['fileName']} audio is not the video duration at 48 kHz")
            if (f["barcode"] is None) != (f["variant"] == "clean"):
                out.append(f"{where}: {f['fileName']} barcode must be on the coded variant only")
            if not f["path"].endswith(f"multiangle-{doc['generator']['sourceHash'][:16]}/{f['fileName']}"):
                out.append(f"{where}: {f['fileName']} path is not this generator source's cache folder")
            if [label["text"] for label in f["labels"]] != ["Sample video (synthetic)", cam["name"]]:
                out.append(f"{where}: {f['fileName']} must burn in the Sample label and its angle name")
    if any(covs[k + 1][0] < covs[k][1] for k in range(len(covs) - 1)):
        out.append(f"{where}: segments overlap")
    if [g["afterSegment"] for g in cam["gaps"]] != list(range(len(covs) - 1)):
        out.append(f"{where}: one gap between each pair of segments")
    for g in cam["gaps"]:
        k = g["afterSegment"]
        if g["matchUs"] != {"startUs": _half_up(covs[k][1]), "endUs": _half_up(covs[k + 1][0])}:
            out.append(f"{where}: gap {k} is not the uncovered span between its segments")
        seg = cam["segments"][k]
        if g["hostUs"]["endUs"] - g["hostUs"]["startUs"] != _half_up(cam["segments"][k + 1]["hostStartUs"]
                                                                     - seg["hostStartUs"] - _q(seg["sourceDurationUs"])):
            out.append(f"{where}: gap {k} host span is not the host clock between segments")
    if cam["journal"] is not None and [s["fileZeroHostUs"] for s in cam["journal"]["segments"]] \
            != [s["hostStartUs"] for s in cam["segments"]]:
        out.append(f"{where}: the journal does not record each segment's file zero")
    for a in cam["audioArrivals"]:
        d = syncfit.sound_delay_us(positions[a["eventId"]], cam["positionMm"], doc["speedOfSound"]["mmPerSecond"])
        arrival = light[a["eventId"]] + d + cam["audio"]["latencyUs"]
        if a["delayUs"] != d or a["latencyUs"] != cam["audio"]["latencyUs"] or a["arrivalMatchUs"] != _half_up(arrival):
            out.append(f"{where}: arrival of {a['eventId']} is not light time + sound delay + latency")
            continue
        k = next((s["segment"] for s, (lo, hi) in zip(cam["segments"], covs) if lo <= arrival < hi), None)
        if a["segment"] != k or (k is None) != (a["reason"] == "notRecording"):
            out.append(f"{where}: arrival of {a['eventId']} is in the wrong segment")
            continue
        if k is not None:
            seg = cam["segments"][k]
            sample = _half_up((arrival - _q(seg["transform"]["offsetUs"])) / rate * 48_000 / US)
            if a["sourceSample"] != sample:
                out.append(f"{where}: arrival of {a['eventId']} is not at its source sample")
            if a["heard"] != (a["reason"] is None) or (cam["audio"]["mode"] == "muted" and a["heard"]):
                out.append(f"{where}: arrival of {a['eventId']} heard/reason disagree")
    if cam["view"] == "covered" and cam["visualEvents"]:
        out.append(f"{where}: a covered lens sees no event")
    for v in cam["visualEvents"]:
        seg = cam["segments"][v["segment"]]
        t, n = light[v["eventId"]], v["frame"]
        last = n + 1 >= seg["frameCount"]
        if not (_match(seg, _source_us(cam, n)) <= t and (last or t < _match(seg, _source_us(cam, n + 1)))):
            out.append(f"{where}: {v['eventId']} is not on screen in frame {n}")
        s = cam["shake"]
        if v["inShake"] != (s is not None and s["segment"] == v["segment"] and s["fromFrame"] <= n < s["toFrame"]):
            out.append(f"{where}: {v['eventId']} shake mark is wrong")
    return out


def _problems(doc: dict) -> list[str]:
    out = []
    events = doc["scene"]["events"]
    light = {e["id"]: Fraction(e["sceneSample"] * US, doc["scene"]["sceneSampleRate"]) for e in events}
    positions = {e["id"]: e["positionMm"] for e in events}
    if any(e["lightTimeUs"] != _half_up(light[e["id"]]) for e in events):
        out.append("an event's lightTimeUs is not its scene sample")
    refs = [c for c in doc["cameras"] if c["reference"]]
    if [c["cameraId"] for c in refs] != [doc["matchClock"]["referenceCameraId"]]:
        out.append("exactly one reference camera, the match clock's")
    if len({c["sourceId"] for c in doc["cameras"]}) != len(doc["cameras"]):
        out.append("barcode source ids must be unique within a profile")
    for cam in doc["cameras"]:
        out += _camera_problems(doc, cam, light, positions)
    expected = []
    for a, b in combinations(doc["cameras"], 2):
        spans = sorted((max(x[0], y[0]), min(x[1], y[1])) for x in (_coverage(a, s) for s in a["segments"])
                       for y in (_coverage(b, s) for s in b["segments"]) if max(x[0], y[0]) < min(x[1], y[1]))
        expected.append({"cameras": [a["cameraId"], b["cameraId"]],
                         "matchUs": [{"startUs": _half_up(lo), "endUs": _half_up(hi)} for lo, hi in spans] or None})
    if doc["sharedCoverage"] != expected:
        out.append("sharedCoverage is not the overlap of the cameras' coverage")
    if doc["hashes"]["renderedWithSourceHash"] != doc["generator"]["sourceHash"]:
        out.append("hashes were rendered from another generator source: run scripts/media/studio/multiangle/generate.py")
    names = sorted(f["fileName"] for c in doc["cameras"] for s in c["segments"] for f in s["files"])
    if sorted(doc["hashes"]["files"]) != names:
        out.append("hashes must cover exactly the profile's files")
    return out


def check_profiles(ctx, rep) -> None:
    docs = _profiles()
    if {d["profile"] for _, d in docs} != TICKET_PROFILES:
        rep.fail("multiangle", f"the ticket's profiles are {sorted(TICKET_PROFILES)}, found {[d['profile'] for _, d in docs]}")
    for rel, doc in docs:
        errors = ctx.schemas.validate(doc, SCHEMAS[truth.SCHEMA])
        if errors:
            rep.fail(rel, "schema: " + "; ".join(errors[:4]))
            continue
        problems = _problems(doc)
        for p in problems:
            rep.fail(rel, p)
        if not problems:
            rep.ok("multi-angle ground truth consistent")


def check_profile_stresses(ctx, rep) -> None:
    """Each profile shows the condition it is named for (ticket S58's list)."""
    docs = {d["profile"]: d for _, d in _profiles()}
    if set(docs) != TICKET_PROFILES:
        rep.fail("multiangle", "profiles missing")
        return

    def cams(pid):
        return [c for c in docs[pid]["cameras"] if not c["reference"]]

    def gap_host(c):
        return [g["hostUs"]["endUs"] - g["hostUs"]["startUs"] for g in c["gaps"]]

    rules = {
        "drift-default": lambda: len(docs["drift-default"]["cameras"]) == 6 and all(
            1_000 <= abs(c["clock"]["driftPpb"]) <= 50_000 for c in cams("drift-default")),
        "drift-stress-300ppm": lambda: [c["clock"]["driftPpb"] for c in cams("drift-stress-300ppm")] == [300_000],
        "restart-41s-journal": lambda: all(gap_host(c) == [GAP_US] and c["journal"] for c in cams("restart-41s-journal")),
        "restart-41s-no-journal": lambda: all(gap_host(c) == [GAP_US] and c["journal"] is None
                                              for c in cams("restart-41s-no-journal")),
        "late-start": lambda: all(c["segments"][0]["matchCoverageUs"]["startUs"] >= 30 * US for c in cams("late-start")),
        "shake": lambda: all(c["shake"] and any(v["inShake"] and v["kind"] != "bounce" for v in c["visualEvents"])
                             for c in cams("shake")),
        "muted": lambda: all(c["audio"]["mode"] == "muted" and not any(a["heard"] for a in c["audioArrivals"])
                             for c in cams("muted")),
        "mixed-fps": lambda: sorted(c["frameRate"]["num"] for c in docs["mixed-fps"]["cameras"]) == [30, 60, 240],
        "vfr-rotated-hdr": lambda: sorted((c["frameTiming"]["kind"], c["rotation"], c["hdr"] or "")
                                          for c in cams("vfr-rotated-hdr")) == [("cfr", 0, "hlg"), ("cfr", 90, ""),
                                                                                 ("vfr", 0, "")],
        "no-shared-coverage": lambda: [p["matchUs"] for p in docs["no-shared-coverage"]["sharedCoverage"]] == [None],
        "opposite-baseline-audio-only": lambda: sorted(c["placement"] for c in docs["opposite-baseline-audio-only"]["cameras"])
        == ["BN", "BS"] and all(c["view"] == "covered" for c in docs["opposite-baseline-audio-only"]["cameras"]),
    }
    for pid, rule in rules.items():
        if rule():
            rep.ok("multi-angle profiles show their condition")
        else:
            rep.fail(f"{truth.FIXTURES}/{pid}.json", "the profile does not show the condition it is named for")


def check_rig(ctx, rep) -> None:
    """The rig's tables are syncfit's sound delays to its placements and reproduce research 4.4 within 0.1 ms."""
    rig = json.loads((FIX / RIG).read_text(encoding="utf-8"))
    errors = ctx.schemas.validate(rig, SCHEMAS[truth.RIG_SCHEMA])
    if errors:
        rep.fail(RIG, "schema: " + "; ".join(errors[:4]))
        return
    mics = {p["code"]: p["positionMm"] for p in rig["placements"]}
    rows = {json.dumps(r["positionMm"], sort_keys=True): r for r in rig["soundDelayTable"]["rows"]}
    for r in rig["soundDelayTable"]["rows"]:
        if r["delaysUs"] != {code: syncfit.sound_delay_us(r["positionMm"], m, 343_000) for code, m in mics.items()}:
            rep.fail(RIG, f"row {r['id']} is not the sound delay to each placement")
    code_of = {json.dumps(m, sort_keys=True): code for code, m in mics.items()}
    checked = 0
    for case in ctx.fixture("vectors/sound-delay.json")["cases"]:
        if "event" not in case:
            continue
        row = rows.get(json.dumps(case["event"], sort_keys=True))
        a = code_of.get(json.dumps(case["mic"], sort_keys=True))
        b = code_of.get(json.dumps(case.get("otherMic"), sort_keys=True)) if "otherMic" in case else None
        if row is None or a is None or ("otherMic" in case and b is None):
            rep.fail(RIG, f"sound-delay vector {case['id']} has no row or placement in the rig")
            continue
        got = row["delaysUs"][a] - (row["delaysUs"][b] if b else 0)
        if abs(Fraction(got, 1000) - Fraction(case["assert"]["docTableMs"])) > Fraction(case["assert"]["toleranceMs"]):
            rep.fail(RIG, f"{case['id']}: {got} us is not the research table's {case['assert']['docTableMs']} ms")
        checked += 1
    if checked >= 45:
        rep.ok("multi-angle rig reproduces research 4.4", checked)
    else:
        rep.fail(RIG, f"only {checked} sound-delay vectors matched the rig")


def _mutations() -> list[tuple[str, str, object]]:
    """(profile, what, mutate(doc)) cases the rules above must refuse."""
    def cam(d, cid):
        return next(c for c in d["cameras"] if c["cameraId"] == cid)

    def shift_offset(d):
        seg = cam(d, "cnw-drift")["segments"][0]
        off = _q(seg["transform"]["offsetUs"]) + Fraction(US, 30)
        seg["transform"]["offsetUs"] = {"num": off.numerator, "den": off.denominator}

    def drop_drift(d):
        cam(d, "cse-stress")["segments"][0]["transform"]["rate"] = {"num": 10**9, "den": 10**9}

    def bend_delay(d):
        next(a for a in cam(d, "bn-covered")["audioArrivals"] if a["heard"])["delayUs"] += 1_000

    def unmark_shake(d):
        next(v for v in cam(d, "csw-shake")["visualEvents"] if v["inShake"])["inShake"] = False

    def invent_overlap(d):
        d["sharedCoverage"][0]["matchUs"] = [{"startUs": 0, "endUs": 1}]

    def forget_restart(d):
        c = cam(d, "cne-restart-journal")
        c["segments"][1]["transform"] = dict(c["segments"][0]["transform"])

    def vfr_as_cfr(d):
        cam(d, "bn-vfr")["frameTiming"] = {"kind": "cfr"}

    def hear_the_muted(d):
        a = next(a for a in cam(d, "cse-muted")["audioArrivals"] if a["reason"] == "muted")
        a["heard"], a["reason"] = True, None

    return [("drift-default", "an offset one output frame wrong", shift_offset),
            ("drift-stress-300ppm", "the 300 ppm drift dropped from the piece", drop_drift),
            ("opposite-baseline-audio-only", "a sound delay 1 ms wrong", bend_delay),
            ("shake", "a shaken anchor unmarked", unmark_shake),
            ("no-shared-coverage", "an invented overlap", invent_overlap),
            ("restart-41s-journal", "the restart's second piece replaced by the first", forget_restart),
            ("vfr-rotated-hdr", "a VFR camera described as CFR", vfr_as_cfr),
            ("muted", "a muted camera hearing a hit", hear_the_muted)]


def check_mutations(ctx, rep) -> None:
    """Each deliberate corruption of a committed ground truth is refused by the rules above."""
    import copy
    docs = {d["profile"]: d for _, d in _profiles()}
    for pid, what, mutate in _mutations():
        if pid not in docs:
            rep.fail("multiangle", f"no {pid} profile to mutate")
            continue
        bad = copy.deepcopy(docs[pid])
        mutate(bad)
        if _problems(bad):
            rep.ok("multi-angle mutations refused")
        else:
            rep.fail(f"{truth.FIXTURES}/{pid}.json", f"{what} was not caught")


SELF_TESTS = {"multiangle-ground-truth": check_profiles, "multiangle-profiles": check_profile_stresses,
              "multiangle-rig": check_rig, "multiangle-mutations": check_mutations}
