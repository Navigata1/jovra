import Foundation
import Testing
@testable import JovraCore

@Test func unknownMajorAndInvalidMediaTimeThrowTypedErrors() throws {
    #expect(throws: ContractError.unsupportedSchemaMajor(2)) {
        try ContractCodec.decode(SchemaVersion.self, from: Data(#""2.0.0""#.utf8))
    }
    #expect(throws: ContractError.invalidMediaTime) {
        try ContractCodec.decode(MediaTime.self, from: Data(#"{"value":1,"timescale":0}"#.utf8))
    }
    for time in [try MediaTime(value: 1001, timescale: 30000), try MediaTime(value: 240001, timescale: 240)] {
        #expect(try ContractCodec.decode(MediaTime.self, from: CanonicalJSON.encode(time)) == time)
    }
}

@Test func roundingDoesNotOverflowOrUsePlatformPercentFormatter() throws {
    #expect(try Percent.pct(n: Int.max, d: Int.max) == 100)
    #expect(throws: PercentError.invalidFraction) { try Percent.pct(n: 2, d: 1) }
    #expect(throws: PercentError.overflow) { try Percent.pool([(Int.max, Int.max), (1, 1)]) }
    let root = try FixtureManifest.repository()
    let urls = FileManager.default.enumerator(at: root.appendingPathComponent("ios/Packages/JovraCore/Sources/JovraCore"), includingPropertiesForKeys: nil)!.allObjects.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    for url in urls {
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.range(of: #"numberStyle\s*=\s*\.percent|PercentFormatStyle|\.formatted\s*\(\s*\.percent|NumberFormatter\s*\("#, options: .regularExpression) == nil)
    }
}

@Test func codecRefusesSilentlyDroppedFieldsAndPreservesVersionText() throws {
    #expect(throws: ContractError.self) {
        try ContractCodec.decode(CourtPoint2D.self, from: Data(#"{"x":0,"y":0,"unexpected":true}"#.utf8))
    }
    let input = Data(#""1.01.000""#.utf8) // The published version regex accepts additive digit sequences.
    let version = try ContractCodec.decode(SchemaVersion.self, from: input)
    #expect(try CanonicalJSON.encode(version) == input)
}
