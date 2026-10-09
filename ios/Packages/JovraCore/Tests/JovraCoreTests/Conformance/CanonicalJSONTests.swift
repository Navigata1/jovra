import Foundation
import Testing
@testable import JovraCore

@Test func canonicalNumbersAndUnicodeHaveIndependentBytes() throws {
    // Hand-derived contract vectors, independent of Swift's encoder.
    let vectors = [
        ("1.0", "1"), ("-0.0", "0"), ("1e-7", "0.0000001"),
        ("1.2300", "1.23"), ("9007199254740993", "9007199254740993"),
        ("1.2e3", "1200"), ("-12.300", "-12.3"),
        (#"{"z":null,"a":{"b":true,"a":[1.0,2.50]}}"#, #"{"a":{"a":[1,2.5],"b":true},"z":null}"#),
        (#"{"text":"See / café 🎾"}"#, #"{"text":"See / café 🎾"}"#)
    ]
    for (input, expected) in vectors {
        #expect(try CanonicalJSON.canonicalize(Data(input.utf8)) == Data(expected.utf8))
    }
}

@Test func malformedAndAmbiguousJSONIsRefused() throws {
    for input in [#"{"a":1,"a":2}"#, "NaN", "Infinity", "01", "1.", #""\ud800""#, #"{"\ud800":1}"#] {
        #expect(throws: (any Error).self) { try CanonicalJSON.canonicalize(Data(input.utf8)) }
    }
    #expect(try CanonicalJSON.canonicalize(Data(#""\ud83c\udfbe""#.utf8)) == Data("\"🎾\"".utf8))
    #expect(try CanonicalJSON.canonicalize(Data(#"{"é":1,"e\u0301":2}"#.utf8)) == Data("{\"e\u{0301}\":2,\"é\":1}".utf8))
}

@Test func persistedDecimalCannotSilentlyLosePrecision() throws {
    let input = Data(#"{"x":0.123456789012345678901234567890123456789012345,"y":0}"#.utf8)
    #expect(throws: ContractError.self) { try ContractCodec.decode(CourtPoint2D.self, from: input) }
}
