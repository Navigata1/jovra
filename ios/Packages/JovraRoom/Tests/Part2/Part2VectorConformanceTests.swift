import Foundation
import JovraRoom
import XCTest

/// spec/room/fixtures/vectors, Part 2 kinds (W02, #271): every case of watch-sample (9), bridge (6), alerts (9),
/// invitation (28), ledger (22) and outbox (8) agrees with the reference. With Part 1's 47 that is all 129.
final class Part2VectorConformanceTests: XCTestCase {
    private func assertAllPass(_ run: () throws -> Part2Runners.Outcome, kind: String,
                               file: StaticString = #filePath, line: UInt = #line) throws {
        let (cases, failures) = try run()
        XCTAssertEqual(cases, RoomVectorKinds.part2[kind], "\(kind) case count", file: file, line: line)
        XCTAssertEqual(failures, [], "\(kind)", file: file, line: line)
    }

    func test_watchSampleVectors() throws { try assertAllPass(Part2Runners.watchSample, kind: "watch-sample") }
    func test_bridgeVectors() throws { try assertAllPass({ try Part2Runners.bridge() }, kind: "bridge") }
    func test_alertVectors() throws { try assertAllPass(Part2Runners.alerts, kind: "alerts") }
    func test_invitationVectors() throws { try assertAllPass(Part2Runners.invitation, kind: "invitation") }
    func test_ledgerVectors() throws { try assertAllPass({ try Part2Runners.ledger() }, kind: "ledger") }
    func test_outboxVectors() throws { try assertAllPass({ try Part2Runners.outbox() }, kind: "outbox") }

    func test_allVectorKindsTogetherAre129Cases() {
        XCTAssertEqual(RoomVectorKinds.counts.values.reduce(0, +), 129)
        XCTAssertEqual(RoomVectorKinds.part2.values.reduce(0, +), 82)
    }

    /// The acceptance map's references into Part 2 vector files resolve to real cases, and every acceptance row a
    /// Part 2 case cites exists in the map.
    func test_acceptanceMapReferencesResolveForPart2() throws {
        let rows = try XCTUnwrap(RoomFixtures.json("acceptance-map.json")["rows"]?.array)
        let rowNumbers = Set(rows.compactMap { $0["row"]?.int })
        let part2Files = Set(RoomVectorKinds.part2.keys.map { "vectors/\($0).json" })
        var caseIds: [String: Set<String>] = [:]
        for file in part2Files {
            caseIds[file] = Set((try RoomFixtures.json(file)["cases"]?.array ?? []).compactMap { $0["id"]?.string })
        }
        var checked = 0
        for row in rows {
            for cover in row["covers"]?.array?.compactMap(\.string) ?? [] {
                let parts = cover.split(separator: "#", maxSplits: 1).map(String.init)
                guard parts.count == 2, part2Files.contains(parts[0]) else { continue }
                XCTAssertTrue(caseIds[parts[0]]?.contains(parts[1]) == true, "acceptance map cites missing \(cover)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 0)
        for file in part2Files {
            for testCase in try RoomFixtures.json(file)["cases"]?.array ?? [] {
                for row in testCase["acceptanceRows"]?.array?.compactMap(\.int) ?? [] {
                    XCTAssertTrue(rowNumbers.contains(row), "\(file)#\(testCase["id"]?.string ?? "?") cites row \(row)")
                }
            }
        }
    }
}
