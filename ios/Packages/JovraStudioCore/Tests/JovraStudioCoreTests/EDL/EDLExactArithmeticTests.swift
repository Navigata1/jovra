import Foundation
import Testing
@testable import JovraStudioCore

/// The EDL's exact arithmetic: session times of a real sync rate need more than 64 bits in their cross products, and a
/// trap or a rounding would change a decision.
@Suite("EDL exact arithmetic")
struct EDLExactArithmeticTests {
    @Test("products beyond Int64 stay exact")
    func largeProducts() {
        let big = EDLInteger(Int.max) * EDLInteger(Int.max)
        #expect(big.description == "85070591730234615847396907784232501249")
        #expect((big - big).isZero)
        #expect((-big).description == "-85070591730234615847396907784232501249")
        #expect(EDLInteger.floorDivide(big, by: EDLInteger(Int.max)) == EDLInteger(Int.max))
        // floor division rounds toward negative infinity
        #expect(EDLInteger.floorDivide(-big - EDLInteger(1), by: EDLInteger(Int.max)).description == "-9223372036854775808")
        #expect(EDLInteger.floorDivide(EDLInteger(-7), by: EDLInteger(2)) == EDLInteger(-4))
    }

    @Test("fractions compare exactly where binary floating point would not")
    func fractionComparison() {
        // 1000300102/1000000000 x 50000/3 µs per frame at 60 fps, 108000 frames on: the extrapolated end of Camera 2's
        // first interval (edl-context vector restart-extrapolated-session: 1 800 660 021 µs after the 119 837 µs start)
        let rate = EDLFraction(1_000_300_102, 1_000_000_000)
        let frameUs = EDLFraction(1_000_000, 60)
        let session = EDLFraction(119_837) + EDLFraction(108_000) * frameUs * rate
        #expect(session.roundedHalfUp == EDLInteger(1_800_660_021))
        let a = EDLFraction(EDLInteger(Int.max) * EDLInteger(3) + EDLInteger(1), EDLInteger(Int.max) * EDLInteger(3))
        #expect(a > EDLFraction(1))
        #expect(a - EDLFraction(1) == EDLFraction(EDLInteger(1), EDLInteger(Int.max) * EDLInteger(3)))
        #expect(EDLFraction(7, 2).ceil == EDLInteger(4) && EDLFraction(-7, 2).ceil == EDLInteger(-3))
        #expect(EDLFraction(5, 2).roundedHalfUp == EDLInteger(3) && EDLFraction(-5, 2).roundedHalfUp == EDLInteger(-2))
    }
}
