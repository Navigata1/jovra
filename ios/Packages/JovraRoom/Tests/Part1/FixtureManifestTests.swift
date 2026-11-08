import Foundation
import XCTest

/// Every file under spec/room/fixtures is accounted for: records and invalid cases by RecordConformanceTests, Part 1
/// vector kinds by VectorConformanceTests, the other kinds by W02 (#271), and the acceptance map here. An unknown
/// kind, an unowned kind or an unconsumed file fails, so a fixture added to spec/room cannot be silently skipped.
final class FixtureManifestTests: XCTestCase {
    func test_everyFixtureFileIsConsumedAndEveryKindIsKnown() throws {
        var unconsumed: [String] = []
        var kinds: [String: String] = [:]
        for file in try RoomFixtures.allFiles() {
            switch file {
            case _ where file.hasPrefix("records/"), _ where file.hasPrefix("invalid/"), "acceptance-map.json":
                continue
            case _ where file.hasPrefix("vectors/"):
                let doc = try RoomFixtures.json(file)
                let kind = try XCTUnwrap(doc["kind"]?.string, file)
                XCTAssertTrue(RoomVectorKinds.all.contains(kind), "\(file): unknown vector kind \(kind)")
                XCTAssertNil(kinds.updateValue(file, forKey: kind), "\(file): kind \(kind) appears twice")
                if let expected = RoomVectorKinds.part1[kind] {
                    XCTAssertEqual(doc["cases"]?.array?.count, expected, "\(file) case count")
                }
            default:
                unconsumed.append(file)
            }
        }
        XCTAssertEqual(unconsumed, [], "fixture files nobody consumes")
        XCTAssertEqual(Set(kinds.keys), RoomVectorKinds.all, "every owned kind has exactly one file")
        XCTAssertEqual(try RoomFixtures.files(in: "records").count, 27)
        XCTAssertEqual(try RoomFixtures.files(in: "invalid").count, 21)
    }

    /// The acceptance map's references into Part 1 fixtures resolve to real cases, and every acceptance row a Part 1
    /// vector cites exists in the map.
    func test_acceptanceMapReferencesResolveForPart1() throws {
        let map = try RoomFixtures.json("acceptance-map.json")
        XCTAssertEqual(map["schemaVersion"]?.string, "jovra.room-fixture.acceptance-map/1")
        let rows = try XCTUnwrap(map["rows"]?.array)
        let rowNumbers = Set(rows.compactMap { $0["row"]?.int })
        var caseIds: [String: Set<String>] = [:]
        for file in try RoomFixtures.files(in: "vectors") + RoomFixtures.files(in: "invalid") {
            caseIds[file] = Set((try RoomFixtures.json(file)["cases"]?.array ?? []).compactMap { $0["id"]?.string })
        }
        let part1Files = Set(RoomVectorKinds.part1.keys.map { "vectors/\($0).json" })
        var checked = 0
        for row in rows {
            for cover in row["covers"]?.array?.compactMap(\.string) ?? [] {
                let parts = cover.split(separator: "#", maxSplits: 1).map(String.init)
                guard parts.count == 2, part1Files.contains(parts[0]) || parts[0].hasPrefix("invalid/") else { continue }
                XCTAssertTrue(caseIds[parts[0]]?.contains(parts[1]) == true, "acceptance map cites missing \(cover)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 0)
        for file in part1Files {
            for testCase in try RoomFixtures.json(file)["cases"]?.array ?? [] {
                for row in testCase["acceptanceRows"]?.array?.compactMap(\.int) ?? [] {
                    XCTAssertTrue(rowNumbers.contains(row), "\(file)#\(testCase["id"]?.string ?? "?") cites row \(row)")
                }
            }
        }
    }
}
