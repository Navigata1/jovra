import JovraCore
import Testing
@testable import Jovra

/// User stories 138 and 357: every percentage is checkable and reads with its fraction and provenance.
@Suite("Fraction presentation")
struct FractionPresentationTests {
    @Test("67% first serves (40 of 60, manual) reads value, fraction and provenance")
    func readsFractionAndProvenance() throws {
        let fraction = FractionPresentation(ratio: try Percent.ratio(n: 40, d: 60), provenance: .manual)
        #expect(fraction.value == "67%")
        #expect(fraction.fraction == "40 of 60")
        #expect(fraction.spokenValue == "67 percent, 40 of 60, manual")
        #expect(fraction.badge == .provenance(.manual))
    }

    @Test("a zero denominator shows an em dash and reads no data")
    func zeroDenominator() throws {
        let fraction = FractionPresentation(ratio: try Percent.ratio(n: 0, d: 0), provenance: .manual)
        #expect(fraction.value == "—")
        #expect(fraction.fraction == nil)
        #expect(fraction.spokenValue == "no data")
    }

    @Test("sample values say so when spoken and badge as Sample")
    func sample() throws {
        let fraction = FractionPresentation(ratio: try Percent.ratio(n: 28, d: 40), provenance: .estimated, isSample: true)
        #expect(fraction.spokenValue == "70 percent, 28 of 40, estimated, sample data")
        #expect(fraction.badge == .sample)
    }

    @Test("half rounds up the shared way: 1 of 8 is 13%")
    func rounding() throws {
        let fraction = FractionPresentation(ratio: try Percent.ratio(n: 1, d: 8), provenance: .reviewed)
        #expect(fraction.value == "13%")
        #expect(fraction.spokenValue == "13 percent, 1 of 8, reviewed")
    }
}
