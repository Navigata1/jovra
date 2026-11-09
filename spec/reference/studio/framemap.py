"""What a renderer must put in every output frame of a compiled `jovra.edit-plan/2`, for barcode fixture sources.

Standard library only, exact arithmetic. Module page: spec/studio/modules/barcode-court.md.

A renderer test compares barcodes directly: it decodes every output frame, reads the S08 barcode
(`jovra.frame-barcode/1`: source id, segment, frame id) and compares it with `frame_map(plan, barcodes)`. The rules (film-engine 2.1 and 3.6):

* **Clock.** Output frame `o` of a live, B-roll or replay segment shows source frame
  `sourceInFrame + floor((o - outputInFrame) * k)`, with `k = sourceFps * speed / outputFps` source frames per output
  frame (the latest source frame presented at or before the output frame's time). A freeze shows `sourceFrame` in every
  frame. A title card shows no source picture.
* **Transitions.** A dissolve or dip of `n` frames into segment B is centred on B's first frame `b`: `h_in = n - n // 2`
  frames before `b` already show B and `h_out = n // 2` frames from `b` still show A (edl.py). A **dissolve** blends A,
  continued past its out-point on its own clock, with B, started before its in-point on its own clock, over
  `[b - h_in, b + h_out)`. A **dip** fades A to forest (#092A25) over `[b - h_in, b)` and B up from forest over
  `[b, b + h_out)`, so only one picture is ever under the forest.
* **Runs.** Consecutive frames that advance by one fixed step on one picture are one run
  `{outFrame, count, picture, ...}`; `picture` is `source` (with `sourceId`, `barcode: [source, segment, frameId]` of
  the run's first frame and `step`, 0 for a freeze), `card` (`templateId`), `dissolve` (`from` and `to`, each a source
  or a card), `dip-out` or `dip-in` (one source or card, `through` the forest colour). A step is a whole number of
  barcode frame ids per output frame; a plan whose clock would need a fractional step is refused here
  (`fractionalStep`), never approximated.

`click_map(plan, clicks)` places every click of every sounding bed piece on the output clock (a 1x bed: output sample =
piece start + source sample - source start), and sets apart the clicks that start inside a piece's fade, where the
renderer attenuates them (`faded`, neither required nor forbidden). `overlay_schedule(plan)` lists every overlay
reference with its output range, the Replay and Paused labels, the card templates and the Sample badge: what a
renderer's sidecar overlay log must contain (S40). `operations(plan)` names the SD6b operations and the finer features
(transition kinds, card templates, overlay kinds, labels, framing, clock) a plan exercises, for the coverage table.
"""

from __future__ import annotations

from fractions import Fraction

from .core import Reject, canonical_sha256, require

RATE = 48_000
FOREST = "#092A25"


def _fps(raw: dict) -> Fraction:
    return Fraction(raw["num"], raw["den"])


class Barcodes:
    """Per source id: the S08 barcode source id and the frame map runs `(frame, segment, frameId, count)`."""

    def __init__(self, table: dict):
        self.table = table

    def payload(self, source_id: str, frame: int) -> list:
        entry = self.table.get(source_id)
        require(entry is not None, "noBarcode", f"{source_id} carries no S08 barcode")
        for run in entry["runs"]:
            if run["frame"] <= frame < run["frame"] + run["count"]:
                return [entry["barcodeSourceId"], run["segment"], run["frameId"] + frame - run["frame"]]
        raise Reject("outsideSource", f"{source_id} has no frame {frame}")


def _segment_clock(seg: dict, sources: dict, out_fps: Fraction):
    """(source id, first source frame, source frames per output frame) for a segment that shows a source, else None."""
    if seg["op"] == "title-card":
        return None
    if seg["op"] == "freeze":
        return seg["sourceId"], Fraction(seg["sourceFrame"]), Fraction(0)
    speed = Fraction(seg["speed"]["num"], seg["speed"]["den"])
    k = _fps(sources[seg["sourceId"]]["proxy"]["fps"]) * speed / out_fps
    return seg["sourceId"], Fraction(seg["sourceInFrame"]), k


def _picture(seg: dict, clock, o: int):
    """What segment `seg` shows at output frame `o` (possibly outside its own range, for a transition handle)."""
    if clock is None:
        return ("card", seg["templateId"])
    sid, first, k = clock
    return ("source", sid, (first + (o - seg["outputInFrame"]) * k).__floor__(), k)


def _frames(plan: dict) -> list:
    """Every output frame's picture as a tuple, in order."""
    out_fps = _fps(plan["output"]["fps"])
    sources = {s["id"]: s for s in plan["sources"]}
    segs = plan["segments"]
    clocks = [_segment_clock(s, sources, out_fps) for s in segs]
    frames = []
    for seg, clock in zip(segs, clocks):
        for o in range(seg["outputInFrame"], seg["outputOutFrame"]):
            frames.append(("plain", _picture(seg, clock, o)))
    for j, seg in enumerate(segs):
        tr = seg["transitionIn"]
        if tr["type"] == "cut":
            continue
        b, n = seg["outputInFrame"], tr["frames"]
        h_out, h_in = n // 2, n - n // 2
        prev = segs[j - 1]
        for o in range(b - h_in, b + h_out):
            a_pic, b_pic = _picture(prev, clocks[j - 1], o), _picture(seg, clocks[j], o)
            if tr["type"] == "dissolve":
                frames[o] = ("dissolve", a_pic, b_pic)
            else:
                frames[o] = ("dip-out", a_pic) if o < b else ("dip-in", b_pic)
    return frames


def _shown(pic: tuple, barcodes: Barcodes) -> dict:
    if pic[0] == "card":
        return {"card": pic[1]}
    return {"sourceId": pic[1], "barcode": barcodes.payload(pic[1], pic[2])}


def _step(pic: tuple) -> int:
    if pic[0] == "card":
        return 0
    k = pic[3]
    require(k.denominator == 1, "fractionalStep", f"{pic[1]} advances {k} frames per output frame; barcode-court "
                                                  "plans keep a whole step")
    return int(k)


def _entry(frame: tuple, barcodes: Barcodes) -> dict:
    kind = frame[0]
    if kind == "plain":
        pic = frame[1]
        if pic[0] == "card":
            return {"picture": "card", "templateId": pic[1]}
        return dict({"picture": "source", "step": _step(pic)}, **_shown(pic, barcodes))
    if kind == "dissolve":
        return {"picture": "dissolve", "from": dict(_shown(frame[1], barcodes), step=_step(frame[1])),
                "to": dict(_shown(frame[2], barcodes), step=_step(frame[2]))}
    return dict({"picture": kind, "through": FOREST, "step": _step(frame[1])}, **_shown(frame[1], barcodes))


def _advance(entry: dict, by: int) -> dict:
    """The entry `by` frames later on the same run (every barcode frame id moved by its step)."""
    def move(e):
        if "barcode" not in e:
            return dict(e)
        source, segment, frame_id = e["barcode"]
        return dict(e, barcode=[source, segment, frame_id + e["step"] * by])
    if entry["picture"] == "dissolve":
        return dict(entry, **{"from": move(entry["from"]), "to": move(entry["to"])})
    return move(entry)


def frame_map(plan: dict, barcodes: Barcodes) -> list:
    """The expected output frame map as runs (module docstring). Raises Reject on a source with no barcode or a
    fractional step."""
    runs: list = []
    for o, frame in enumerate(_frames(plan)):
        entry = _entry(frame, barcodes)
        if runs:
            last = runs[-1]
            head = {k: v for k, v in last.items() if k not in ("outFrame", "count")}
            if _advance(head, last["count"]) == entry:
                last["count"] += 1
                continue
        runs.append(dict({"outFrame": o, "count": 1}, **entry))
    return runs


def expand(runs: list) -> list:
    """Every output frame's entry, from the runs (what a renderer test compares frame by frame)."""
    out = []
    for run in runs:
        head = {k: v for k, v in run.items() if k not in ("outFrame", "count")}
        out += [_advance(head, i) for i in range(run["count"])]
    return out


def frame_map_sha256(runs: list) -> str:
    return canonical_sha256(runs)


# ----- clicks ------------------------------------------------------------------------------------------------------

def click_map(plan: dict, clicks: dict) -> dict:
    """{"clicks": [...], "faded": [...]}: each {outSample, outFrame, sourceId, sourceSample}. `clicks` maps a source id
    to its click onsets (48 kHz samples on the source's own audio clock)."""
    out_fps = _fps(plan["output"]["fps"])
    sources = {s["id"]: s for s in plan["sources"]}
    found, faded = [], []
    for p in plan["audio"]["bed"]:
        if p["route"] == "silence":
            continue
        src_fps = _fps(sources[p["sourceId"]]["proxy"]["fps"])
        s0 = Fraction(p["sourceInFrame"]) * RATE / src_fps
        o0, o1 = Fraction(p["outputInFrame"]) * RATE / out_fps, Fraction(p["outputOutFrame"]) * RATE / out_fps
        lo = o0 + Fraction(p["fadeInMs"]) * RATE / 1000
        hi = o1 - Fraction(p["fadeOutMs"]) * RATE / 1000
        for sample in clicks.get(p["sourceId"], []):
            at = o0 + sample - s0
            if not o0 <= at < o1:
                continue
            require(at.denominator == 1, "fractionalSample", "a bed piece starts between two audio samples")
            entry = {"outSample": int(at), "outFrame": (at * out_fps / RATE).__floor__(), "sourceId": p["sourceId"],
                     "sourceSample": sample}
            (found if lo <= at < hi else faded).append(entry)
    return {"clicks": found, "faded": faded}


# ----- overlays ----------------------------------------------------------------------------------------------------

def overlay_schedule(plan: dict) -> dict:
    """What the renderer's overlay log must hold: every overlay reference over its segment, the labels and cards, and
    the Sample badge over the whole film when the plan is Sample."""
    overlays, labels, cards = [], [], []
    for seg in plan["segments"]:
        span = {"outputInFrame": seg["outputInFrame"], "outputOutFrame": seg["outputOutFrame"], "segment": seg["id"]}
        for ref in seg["overlayRefs"]:
            overlays.append(dict(span, kind=ref["kind"], refId=ref["refId"], provenance=ref["provenance"],
                                 eventRevision=ref["eventRevision"]))
        if seg.get("labelTemplateId"):
            labels.append(dict(span, templateId=seg["labelTemplateId"]))
        if seg["op"] == "title-card":
            cards.append(dict(span, templateId=seg["templateId"], textRefs=list(seg["textRefs"])))
    total = plan["output"]["totalFrames"]
    badge = {"outputInFrame": 0, "outputOutFrame": total} if plan["sample"] else None
    return {"overlays": overlays, "labels": labels, "cards": cards, "sampleBadge": badge}


# ----- operations --------------------------------------------------------------------------------------------------

SEGMENT_OP = {"live": "live", "broll": "broll", "replay": "replay", "freeze": "freeze", "title-card": "card"}


def operations(plan: dict) -> set:
    """The SD6b operations a plan exercises, plus the finer features named `<op>.<detail>`."""
    ops = set()
    out_fps = _fps(plan["output"]["fps"])
    sources = {s["id"]: s for s in plan["sources"]}
    for seg in plan["segments"]:
        ops.add(SEGMENT_OP[seg["op"]])
        tr = seg["transitionIn"]["type"]
        ops |= {"transition", f"transition.{tr}"}
        if seg["op"] == "title-card":
            ops.add("card.recording-gap" if seg["templateId"] == "card.recording-gap" else "card.title")
        if seg["op"] == "replay":
            src_fps = _fps(sources[seg["sourceId"]]["proxy"]["fps"])
            ops.add(f"replay.1/{seg['speed']['den']}-from-{src_fps}fps-at-{out_fps}fps")
        if seg.get("labelTemplateId"):
            ops.add(seg["labelTemplateId"])
        for ref in seg["overlayRefs"]:
            ops |= {"overlay", f"overlay.{ref['kind']}"}
        if "framing" in seg:
            ops.add(f"framing.{seg['framing']['mode']}")
    if any(seg["overlayRefs"] for seg in plan["segments"]):
        ops.add("overlay.provenance-chip")   # every overlay reference carries the provenance its chip shows
    if plan["sample"]:
        ops.add("badge.sample")
    ops.add("grade")
    ops.add(f"grade.{plan['grade']['presetId']}")
    for p in plan["audio"]["bed"]:
        ops.add(p["route"])
    ops.add(f"output.{plan['output']['aspect']}")
    if plan["cleanAlternate"]:
        ops.add("clean-alternate")
    return ops
