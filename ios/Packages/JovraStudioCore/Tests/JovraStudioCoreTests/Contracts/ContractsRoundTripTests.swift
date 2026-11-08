import Foundation
import Testing
import JovraCore
import JovraStudioCore

/// STU-01: every shared record (and contract data file) whose schemaVersion has a registered decoder decodes strictly
/// and re-encodes byte-identically to its canonical form (core T03's writer, ADR-0029). The count is printed, never
/// asserted as a literal, so a contract ticket that adds a record never edits this file.
@Suite("Studio contracts: record round-trips")
struct ContractsRoundTripTests {
    static func documents() throws -> [(name: String, data: Data)] {
        let root = StudioFixtures.repositoryRoot()
        var out: [(String, Data)] = []
        for folder in ["spec/studio/fixtures/records", "spec/studio/contracts"] {
            let url = root.appendingPathComponent(folder)
            for name in try FileManager.default.contentsOfDirectory(atPath: url.path).filter({ $0.hasSuffix(".json") }).sorted() {
                out.append(("\(folder.split(separator: "/").last!)/\(name)", try Data(contentsOf: url.appendingPathComponent(name))))
            }
        }
        return out
    }

    @Test("every record with a registered decoder decodes and re-encodes byte-identically")
    func recordsRoundTrip() throws {
        let consumption = StudioConsumption.discovered
        #expect(consumption.conflicts.isEmpty, "\(consumption.conflicts)")
        var decoded: [String: Int] = [:]
        var unregistered: [String] = []
        for document in try Self.documents() {
            let header = try StudioRecordHeader(json: document.data)
            guard let decoder = consumption.decoders[header.schemaVersion.description] else {
                unregistered.append("\(document.name) (\(header.schemaVersion))")
                continue
            }
            let canonical = try CanonicalJSON.canonicalize(document.data)
            let reencoded = try decoder.roundTrip(document.data)
            #expect(reencoded == canonical, "\(document.name) does not re-encode to its canonical bytes")
            decoded[decoder.schemaVersion, default: 0] += 1
        }
        let total = decoded.values.reduce(0, +)
        print("Studio round-trips: \(total) records byte-identical across \(decoded.count) schemas")
        for (version, count) in decoded.sorted(by: { $0.key < $1.key }) { print("  \(version): \(count)") }
        print("Studio records without a registered Swift decoder (their pages stay pending): \(unregistered.joined(separator: ", "))")
        #expect(total > 0)
        for version in consumption.decoders.keys.sorted() {
            #expect(decoded[version, default: 0] > 0, "registered decoder \(version) has no record fixture")
        }
    }

    @Test("the typed model carries the fixture's values, not just its bytes")
    func typedValuesMatchTheFixture() throws {
        let data = try StudioFixtures.data("records/edit-plan.court-memories-storyboard.json")
        let tree = try StudioJSONParser.parse(data)
        let plan = try StudioContractCodec.decode(EditPlan.self, from: data)

        guard case .array(let segments)? = tree["segments"], case .string(let firstId)? = segments.first?["id"] else {
            Issue.record("fixture has no segments")
            return
        }
        #expect(plan.segments.count == segments.count)
        let first: String = switch plan.segments[0] {
        case .live(let s): s.id
        case .broll(let s): s.id
        case .replay(let s): s.id
        case .freeze(let s): s.id
        case .titleCard(let s): s.id
        }
        #expect(first == firstId)
        guard case .number(let fps)? = tree["output"]?["fps"]?["num"] else {
            Issue.record("fixture has no output fps")
            return
        }
        #expect(plan.output.fps.num == Int(fps.text))
    }

    @Test("a decoded record re-encodes through the codec and decodes to the same value")
    func encodeDecodeIsStable() throws {
        let lock = try StudioContractCodec.decode(ProjectLock.self, from: StudioFixtures.data("records/project-lock.json"))
        let again = try StudioContractCodec.decode(ProjectLock.self, from: StudioContractCodec.encode(lock))
        #expect(again == lock)
        #expect(lock.sample == true)
    }
}
