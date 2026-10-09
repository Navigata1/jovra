import Foundation
import Testing
@testable import JovraCore

@Test func independentCanonicalNegativeControls() throws {
    for input in [#"{"a":1,"\u0061":2}"#, #"{"x":{"a":1,"a":2}}"#, #"{"x":NaN}"#, #"{"x":Infinity}"#, #"{"x":-Infinity}"#, #"[1,]"#, #"{"a":1,}"#, #""\udc00""#, #""\ud800x""#] {
        #expect(throws: (any Error).self) { try CanonicalJSON.canonicalize(Data(input.utf8)) }
    }
    #expect(throws: (any Error).self) { try CanonicalJSON.canonicalize(Data([34, 255, 34])) }
    #expect(try CanonicalJSON.canonicalize(Data(#"{"\ud83c\udfbe":1,"é":-0.0,"e\u0301":1e-7}"#.utf8)) == Data("{\"e\u{0301}\":0.0000001,\"é\":0,\"🎾\":1}".utf8))
}
@Test func independentCodecNegativeControls() throws {
    #expect(throws: ContractError.documentWouldLoseData) { try ContractCodec.decode(CourtPoint2D.self, from: Data(#"{"x":0,"y":0,"future":true}"#.utf8)) }
    #expect(throws: (any Error).self) { try ContractCodec.decode(CourtPoint2D.self, from: Data(#"{"x":null,"y":0}"#.utf8)) }
    #expect(throws: (any Error).self) { try ContractCodec.decode(CourtPoint2D.self, from: Data(#"{"y":0}"#.utf8)) }
    #expect(throws: ContractError.unsupportedSchemaMajor(2)) { try ContractCodec.decode(SchemaVersion.self, from: Data(#""2.1.0""#.utf8)) }
    #expect(try ContractCodec.decode(SchemaVersion.self, from: Data(#""1.999.000""#.utf8)).rawValue == "1.999.000")
    #expect(try ContractCodec.decode(MediaTime.self, from: Data(#"{"value":9007199254740993,"timescale":240}"#.utf8)).value == 9007199254740993)
    #expect(throws: (any Error).self) { try ContractCodec.decode(MediaTime.self, from: Data(#"{"value":9223372036854775808,"timescale":240}"#.utf8)) }
    #expect(throws: ContractError.numericPrecisionExceeded("1e-999")) { try ContractCodec.decode(CourtPoint2D.self, from: Data(#"{"x":1e-999,"y":0}"#.utf8)) }
    #expect(try ContractCodec.decode(ContractNullable<Int>.self, from: Data("null".utf8)) == .null)
}
