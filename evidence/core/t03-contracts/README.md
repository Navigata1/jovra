# T03 implementation evidence

Scope: Foundation-only shared Swift contracts; no native app/simulator/device work, no Studio rendering,
no Android/watch implementation and no validated analysis promotion. Base T02 main d36e170 plus merged
canonical-vocabulary PR328 (15bc44a). Exact final implementation head is recorded by the independent review.

Red-to-green public seams are retained: canonical encoder (01–02), session document (03–04), registry (05,
08), pct (09–10), units (11–12), decimal precision refusal (13–14), manifest discovery (17–18), codec field-loss
and version text (21–22), stored decimal leading zeroes (26–27), and native output validator (20,28).
Intermediate files 06 and 16 were named as planned green attempts but contain compilation failures; 08/18/29
are the authoritative successful successors. File 19 contains an overbroad percent-source-scan failure caused
by an ordinary `self.percent` property; the final scan targets formatter APIs and passes in 29. No failure was
removed or represented as a successful run.

Final macOS `swift test`: **30 tests in 4 suites passed** (29-swift-final.txt), consuming 14 fixture/record kinds
by file-discovered runners, including 13 independent canonical vectors, 32 pct vectors, 31 units vectors and 36
record documents. The pending list is exactly jovra.fixture.scoring, jovra.fixture.stats, jovra.fixture.sample.
The XCTest compatibility runner prints zero XCTest tests; the Swift Testing runner reports 30 actual tests.

`30-encoded-final.txt`: 36/36 Swift outputs schema-valid and independently canonical byte-identical to the
source fixtures. `31-reference-final.txt`: existing reference validator passes. `28-validator-final.txt`: three
subprocess negative tests refuse unknown kinds, malformed documents and empty encoded folders. The actual
SwiftPM generator subprocess rejects duplicate runner ownership with exit 1 (25). Fresh Linux CI remains
required before merge; local macOS success does not substitute for it.

Publication follow-up: the independent reviewer accepted implementation head `192f53f` and its 30 Swift tests;
the complete review and small control logs are in `evidence/ios/t03-independent-review`. The publication commit
adds a permanent public test for trailing LF/CRLF/CR decimal-string rejection to check the Linux Foundation
boundary. This is a regression guard for an independently tested passing behavior, not a claimed new defect/fix.
`32-swift-publication.txt` reports **31 Swift tests passing**, `33-encoded-publication.txt` repeats 36/36 independent
schema/canonical checks, and `34-python-publication.txt` reports **82 Python tests passing**. No implementation changed
after the independently accepted head; fresh required CI must bind the publication head.

Fresh Linux CI at publication head `51850d8` exposed a platform difference: all six trailing newline controls
unexpectedly succeeded on Linux, although they refused on macOS. The red job output is retained in
`35-linux-decimal-newline-red.txt` (run 37941325437). The correction checks that the lexical regex match spans
the entire input token, since `$` may match before a terminal newline and Foundation Decimal parsing differs
by host. The test remains intact. `36-swift-linux-fix-macos.txt`, `37-encoded-linux-fix.txt` and
`38-python-linux-fix.txt` bind the local correction; a fresh Linux CI result is still required to verify it there.
