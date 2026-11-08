import Foundation
import JovraCore
import JovraRoom
import XCTest

/// spec/room/fixtures/records and invalid: every valid record decodes strictly, passes its record rule and
/// re-encodes to its canonical bytes; every invalid case is rejected by the layer (and code) the fixture names.
final class RecordConformanceTests: XCTestCase {
    private var registry: RoomCapabilityRegistry!

    override func setUpWithError() throws {
        registry = RoomCapabilityRegistry(statuses: try RoomFixtures.registryStatuses())
    }

    func test_all27RecordsDecodeStrictlyPassTheirRuleAndRoundTripCanonically() throws {
        let files = try RoomFixtures.files(in: "records")
        XCTAssertEqual(files.count, 27, "records/ file count")
        for file in files {
            let data = try RoomFixtures.data(file)
            let record: RoomRecord
            do { record = try RoomRecord.decode(data) } catch {
                XCTFail("\(file): strict decoding refused a valid record: \(error)"); continue
            }
            XCTAssertEqual(record.schemaVersion, try RoomFixtures.json(file)["schemaVersion"]?.string, file)
            XCTAssertNoThrow(try record.checkRules(registry: registry), file)
            XCTAssertEqual(String(decoding: try record.canonicalData(), as: UTF8.self),
                           String(decoding: try CanonicalJSON.canonicalize(data), as: UTF8.self), file)
        }
    }

    func test_all103InvalidCasesAreRejectedByTheExpectedLayer() throws {
        var tally: [String: Int] = [:]
        for file in try RoomFixtures.files(in: "invalid") {
            let doc = try RoomFixtures.json(file)
            XCTAssertEqual(doc["schemaVersion"]?.string, "jovra.room-fixture.invalid-cases/1", file)
            let base = try RoomFixtures.record(try XCTUnwrap(doc["base"]?.string, file))
            for testCase in try XCTUnwrap(doc["cases"]?.array, file) {
                let ref = CaseRef(file: file, id: testCase["id"]?.string ?? "?")
                let layer = try XCTUnwrap(testCase["expect"]?["layer"]?.string, "\(ref)")
                tally[layer, default: 0] += 1
                let mutated = try JSONPatch.apply(try XCTUnwrap(testCase["patch"], "\(ref)"), to: base)
                let decoded = Result { try RoomRecord.decode(try mutated.data()) }
                switch (layer, decoded) {
                case ("schema", .success):
                    XCTFail("\(ref): strict decoding accepted a schema-invalid record")
                case ("schema", .failure(let error)):
                    XCTAssertTrue(error is RoomDecodingError, "\(ref): \(error)")
                case ("reference", .failure(let error)):
                    XCTFail("\(ref): should decode and fail its rule; decoding said \(error)")
                case ("reference", .success(let record)):
                    let expected = testCase["expect"]?["code"]?.string
                    do {
                        try record.checkRules(registry: registry)
                        XCTFail("\(ref): rule accepted; expected \(expected ?? "?")")
                    } catch let violation as RoomRuleViolation {
                        XCTAssertEqual(violation.code.rawValue, expected, "\(ref)")
                    }
                default:
                    XCTFail("\(ref): unknown layer \(layer)")
                }
            }
        }
        XCTAssertEqual(tally, ["schema": 61, "reference": 42])
    }

    func test_unknownSchemaVersionIsRefused() throws {
        let doc = JSONValue.object(["schemaVersion": .string("jovra.room.telemetry/1")])
        XCTAssertThrowsError(try RoomRecord.decode(try doc.data())) { error in
            XCTAssertEqual(error as? RoomDecodingError, .unknownSchemaVersion("jovra.room.telemetry/1"))
        }
    }

    /// The typed decoders are public, so they refuse unknown properties on their own, not only through
    /// RoomRecord.decode's canonical round-trip guard.
    func test_typedDecodersRefuseUnknownPropertiesOnTheirOwn() throws {
        let patched = try JSONPatch.apply(
            .array([.object(["op": .string("add"), "path": .string("/devices/0/freshness"), "value": .string("Fresh")])]),
            to: RoomFixtures.record("room-snapshot"))
        XCTAssertThrowsError(try JSONDecoder().decode(RoomSnapshotRecord.self, from: patched.data())) { error in
            XCTAssertEqual(error as? RoomDecodingError, .schema(path: "/devices/0/freshness", reason: "property not allowed"))
        }
        let command = try JSONPatch.apply(
            .array([.object(["op": .string("add"), "path": .string("/callbackUrl"), "value": .string("x")])]),
            to: RoomFixtures.record("command.point-won"))
        XCTAssertThrowsError(try JSONDecoder().decode(RoomCommand.self, from: command.data()))
    }

    func test_duplicateJSONKeysAreRefused() throws {
        let text = #"{"schemaVersion":"jovra.room.join-reveal/1","inviteId":"inv-c2","inviteId":"inv-c3","#
            + #""sessionId":"sample-jon-alex","hostEpoch":3,"guestNonce":"2V2bl9x1tlTmFxQnwkpQqg"}"#
        XCTAssertThrowsError(try RoomRecord.decode(Data(text.utf8)))
    }
}
