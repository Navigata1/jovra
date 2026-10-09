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
