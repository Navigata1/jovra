import Testing
import JovraCore

@Suite("WCAG contrast")
struct ContrastTests {
    private let white = SRGBColor(red: 1, green: 1, blue: 1)
    private let black = SRGBColor(red: 0, green: 0, blue: 0)

    @Test("black on white is the maximum 21:1")
    func blackOnWhite() {
        #expect(abs(black.contrastRatio(with: white) - 21.0) < 0.001)
    }

    @Test("#767676 on white is the well-known 4.54:1 AA boundary grey")
    func aaBoundaryGrey() throws {
        let grey = try #require(SRGBColor(hex: "#767676"))
        let ratio = grey.contrastRatio(with: white)
        #expect(abs(ratio - 4.54) < 0.01)
    }

    @Test("contrast ratio is symmetric")
    func symmetric() throws {
        let forest = try #require(SRGBColor(hex: "092a25"))
        let chartreuse = try #require(SRGBColor(hex: "#D7F56A"))
        #expect(forest.contrastRatio(with: chartreuse) == chartreuse.contrastRatio(with: forest))
    }

    @Test("malformed hex strings are rejected", arguments: [
        "", "#FFF", "#GGGGGG", "#1234567", "12 456",
        // UInt32(_:radix:) alone accepts a leading sign; these must still be rejected.
        "+12345", "#+FFFFF", "-00000", "##12345", "0x1234", "１２３４５６",
    ])
    func malformedHex(_ input: String) {
        #expect(SRGBColor(hex: input) == nil)
    }

    @Test("normal text needs 4.5:1, large text and UI parts need 3:1")
    func requirements() throws {
        let grey = try #require(SRGBColor(hex: "#949494")) // ≈ 3.03:1 on white
        #expect(!ContrastRequirement.normalText.isMet(by: grey, on: white))
        #expect(ContrastRequirement.largeText.isMet(by: grey, on: white))
        #expect(ContrastRequirement.nonText.isMet(by: grey, on: white))
        #expect(ContrastRequirement.normalText.minimumRatio == 4.5)
    }
}
