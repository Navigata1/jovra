# Independent fragmented-layout SPEC review

Candidatec93cfdfb26cbba90d78437ce2deca9a938fd36cd vs current main3ae5caa2bb2cff78e9d9b76b9a28a092faf54cf6; scoped streaming container-boundary helper, not full issue18/T16 recovery. Read full issue18, helper/tests and scope/evidence qualifiers.

SPEC ACCEPT:0 bounded findings. File is opened read-only without following a final symlink; descriptor verifies nonempty regular file. Fixed-size8/16-byte headers bound seeking/arithmetic to descriptor length, cap box count, require ftyp/moov ordering and complete moof/mdat pairs, refuse malformed/zero-unbounded sizes. Completed prefix candidates survive a torn tail; payloads are never loaded into memory or rewritten. Only candidate boundaries are returned; decoding/adoption is explicitly separate.

Two public tests use hand-written non-playable box bytes to test boundary positions, partial tails, malformed sizes, missing headers and symlink refusal. Those tests prove layout behavior only. No playback, recovered media, measured seconds lost, partial-recovery report, reset/resume, scanner idempotence or atomic adoption claim is made. These full T16 requirements remain pending for subsequent source/runtime slices. No scope creep or wrong bounded helper behavior found. This static review did not rerun package tests and does not supply Standards acceptance.

## Subsequent independent finding

Root reproduced/identified a named-FIFO liveness gap after the initial static review: read-only open can block before fstat rejects a nonregular file. Initial c93 parser-safety acceptance is now provisional/held; this static report did not exercise that boundary. T02 is reproducing and fixing it with an explicit public refusal control. A corrected exact-source rebind is required before publication acceptance. Original static scope/tests and this finding trail are retained honestly.

## FIFO correction and atomic-adoption prerequisite rebind

SPEC ACCEPT bounded prerequisites at dd1cebe10298765a47dc80713fdae3e1b5c3c1d2, including9e64d45a47a329a743a6833af21174a4b812f3cd, against3ae5caa. Independently read exact source/test delta and producer activation/green logs. The previously reported FIFO blocker is repaired by O_NONBLOCK before fstat; public no-writer FIFO control is activated in12, then returns unsafePath in2ms in13. Earlier nonactivated/setup attempts remain unqualified, and neither fixed-size structural test bytes nor this refusal control imply playable media.

The originating spec requires recovery from journal/segments, decoding to the end (stories94–95; architecture Recovery), preservation of playable partial footage/reasons (story100), and independent facets/atomic writes. applyRecoveredCapture is an intentionally bounded metadata seam, not the scanner: it requires an explicit recovery report, shares the existing single recording/marks/original transaction, preserves previously edited mark IDs and independent match/analysis/review/archive facets, and forces Sample for synthetic capture. The public out-of-space/reopen/retry test checks unchanged metadata on failure, explicit partial/unknown lost suffix, report retention and idempotent bytes; its referenced media path makes no actual-decode claim. No missing/wrong/out-of-scope findings within these prerequisites.

Full decoded-prefix verification, scanner launch adoption, raw journal/segment fingerprints, stable recovery receipt, force-kill loss bound, media-services reset and physical power-loss acceptance remain pending. No compiler/simulator was run by this SPEC reviewer; producer3layout/FIFO and2atomic/handoff controls are separately sourced. This addendum replaces the earlier HELD FIFO safety qualifier only for this corrected exact source.
