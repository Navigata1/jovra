import Foundation
import JovraCore
import JovraRoom

/// Runs the Part 1 vector kinds against the package and returns one message per failing case. The runners take the
/// rule under test as a parameter so the mutation tests can hand them a deliberately broken rule and prove the
/// fixtures catch it; the conformance tests hand them the real one and require no failures.
enum VectorRunners {
    struct UnknownOp: Error, CustomStringConvertible {
        let ref: CaseRef
        let op: String
        var description: String { "\(ref): unknown op \(op)" }
    }

    // MARK: freshness

    struct FreshnessInput: Decodable {
        let senderAgeMs: Int
        let sinceAcceptMs: Int
        let transitBounded: Bool
        let baselineValid: Bool
        let transitMs: Int?
    }

    /// The outcome in the fixture's terms: a freshness word, or `{"error": code}`.
    typealias FreshnessClassifier = (FreshnessInput) -> JSONValue

    static func liveFreshness(_ input: FreshnessInput) -> JSONValue { classify(input, policy: .proposal) }

    static func classify(_ i: FreshnessInput, policy: FreshnessPolicy) -> JSONValue {
        do {
            let freshness = try FreshnessRule.classify(senderAgeMs: i.senderAgeMs, sinceAcceptMs: i.sinceAcceptMs,
                                                       transitBounded: i.transitBounded, transitMs: i.transitMs,
                                                       baselineValid: i.baselineValid, policy: policy)
            return .string(freshness.rawValue)
        } catch {
            return .object(["error": .string(error.code)])
        }
    }

    static func freshness(_ classify: FreshnessClassifier = liveFreshness) throws -> (cases: Int, failures: [String]) {
        let file = "vectors/freshness.json"
        let cases = try cases(of: file, kind: "freshness")
        var failures: [String] = []
        for testCase in cases {
            let ref = CaseRef(file: file, id: testCase["id"]?.string ?? "?")
            let input = try XCTUnwrapValue(testCase["input"], ref).decode(FreshnessInput.self)
            let got = classify(input)
            if got != testCase["expect"] { failures.append("\(ref): got \(got), expected \(testCase["expect"]!)") }
        }
        return (cases.count, failures)
    }

    // MARK: phone-status

    struct Observation: Decodable {
        let transitBounded: Bool
        let transitMs: Int?
        let processBaselineId: String
        let acceptedAtMonoMs: Int
        var value: ReceiverObservation {
            ReceiverObservation(transitBounded: transitBounded, transitMs: transitMs,
                                processBaselineId: processBaselineId, acceptedAtMonoMs: acceptedAtMonoMs)
        }
    }

    /// Lets a mutation rewrite the observation before the board reads it.
    typealias ObservationMutation = (ReceiverObservation) -> ReceiverObservation

    static func phoneStatus(mutate: ObservationMutation = { $0 }) throws -> (cases: Int, failures: [String]) {
        let file = "vectors/phone-status.json"
        let cases = try cases(of: file, kind: "phone-status")
        let base = try RoomFixtures.record("room-snapshot")
        var failures: [String] = []
        for testCase in cases {
            let ref = CaseRef(file: file, id: testCase["id"]?.string ?? "?")
            let snapshot = try snapshotRecord(JSONPatch.apply(XCTUnwrapValue(testCase["snapshotPatch"], ref), to: base))
            let observation = try XCTUnwrapValue(testCase["observation"], ref).decode(Observation.self).value
            let board = try RoomStatusBoard.phone(snapshot, observation: mutate(observation),
                                                  nowMonoMs: XCTUnwrapValue(testCase["nowMonoMs"]?.int, ref),
                                                  currentBaselineId: XCTUnwrapValue(testCase["currentBaselineId"]?.string, ref),
                                                  localDeviceId: testCase["localDeviceId"]?.string)
            let freshness = JSONValue.object(Dictionary(uniqueKeysWithValues: board.rows.map {
                ($0.deviceId, JSONValue.string($0.freshness.rawValue))
            }))
            let expect = try XCTUnwrapValue(testCase["expect"], ref)
            if freshness != expect["freshness"] { failures.append("\(ref) freshness: got \(freshness)") }
            if try countsValue(board.counts) != expect["counts"] { failures.append("\(ref) counts: got \(board.counts)") }
        }
        return (cases.count, failures)
    }

    // MARK: display

    static func display() throws -> (cases: Int, failures: [String]) {
        let file = "vectors/display.json"
        let cases = try cases(of: file, kind: "display")
        var failures: [String] = []
        for testCase in cases {
            let ref = CaseRef(file: file, id: testCase["id"]?.string ?? "?")
            let report = try reportValue(XCTUnwrapValue(testCase["device"], ref))
            let row: StatusRow
            if testCase["isLocal"]?.bool == true {
                row = try StatusRow.local(report, localElapsedMs: XCTUnwrapValue(testCase["localElapsedMs"]?.int, ref))
            } else {
                let freshness = try XCTUnwrapValue(Freshness(rawValue: testCase["freshness"]?.string ?? ""), ref)
                row = StatusRow.remote(report, freshness: freshness, ageMs: testCase["ageMs"]?.int)
            }
            if rowValue(row) != testCase["expect"] { failures.append("\(ref): got \(rowValue(row))") }
        }
        return (cases.count, failures)
    }

    // MARK: disconnect

    static func disconnect() throws -> (cases: Int, failures: [String]) {
        let file = "vectors/disconnect.json"
        let cases = try cases(of: file, kind: "disconnect")
        var failures: [String] = []
        for testCase in cases {
            let ref = CaseRef(file: file, id: testCase["id"]?.string ?? "?")
            let local = try reportValue(XCTUnwrapValue(testCase["local"], ref))
            let remote = try XCTUnwrapValue(testCase["remote"]?.array, ref).map(reportValue)
            let got = try RoomDisconnectOutcome.onRoomDisconnect(local: local, remote: remote)
            let exp = try XCTUnwrapValue(testCase["expect"], ref)
            if .string(got.localCaptureState.rawValue) != exp["localCaptureState"] { failures.append("\(ref) local") }
            if !got.commandsIssued.isEmpty || exp["commandsIssued"] != .array([]) { failures.append("\(ref) commands") }
            if try countsValue(got.board.counts) != exp["counts"] { failures.append("\(ref) counts: \(got.board.counts)") }
            let frozen = JSONValue.object(Dictionary(uniqueKeysWithValues: got.board.rows.map {
                ($0.deviceId, JSONValue.int($0.elapsedMs))
            }))
            if frozen != exp["frozenElapsedMs"] { failures.append("\(ref) frozen: \(frozen)") }
            let may = JSONValue.object(Dictionary(uniqueKeysWithValues: got.board.rows.map {
                ($0.deviceId, JSONValue.bool($0.mayStillBeRecording))
            }))
            if may != exp["mayStillBeRecording"] { failures.append("\(ref) may: \(may)") }
        }
        return (cases.count, failures)
    }

    // MARK: snapshot

    static func snapshot() throws -> (cases: Int, failures: [String]) {
        let file = "vectors/snapshot.json"
        let cases = try cases(of: file, kind: "snapshot")
        let base = try RoomFixtures.record("room-snapshot")
        var failures: [String] = []
        for testCase in cases {
            let ref = CaseRef(file: file, id: testCase["id"]?.string ?? "?")
            let initial = try XCTUnwrapValue(testCase["initial"], ref)
            var receiver = SnapshotReceiver(
                sessionId: try XCTUnwrapValue(initial["sessionId"]?.string, ref),
                hostEpoch: try XCTUnwrapValue(initial["hostEpoch"]?.int, ref),
                hostKey: try XCTUnwrapValue(initial["hostKey"]?.string, ref),
                hostDeviceId: try XCTUnwrapValue(initial["hostDeviceId"]?.string, ref),
                members: try XCTUnwrapValue(initial["members"]?.array, ref).compactMap(\.string),
                rosterRevision: try XCTUnwrapValue(initial["rosterRevision"]?.int, ref))
            for (index, step) in try XCTUnwrapValue(testCase["steps"]?.array, ref).enumerated() {
                let where_ = ref.step(index)
                switch step["op"]?.string {
                case "accept":
                    let env = try snapshotRecord(JSONPatch.apply(XCTUnwrapValue(step["envelopePatch"], where_), to: base))
                    let got = receiver.accept(env).rawValue
                    if .string(got) != step["expect"] { failures.append("\(where_): got \(got)") }
                case "reconcile":
                    let got = receiver.reconcile(
                        newEpoch: try XCTUnwrapValue(step["newEpoch"]?.int, where_),
                        hostKey: try XCTUnwrapValue(step["hostKey"]?.string, where_),
                        hostDeviceId: try XCTUnwrapValue(step["hostDeviceId"]?.string, where_),
                        approvedHostKeys: Set(try XCTUnwrapValue(step["approvedHostKeys"]?.array, where_).compactMap(\.string)))
                    if .string(got.rawValue) != step["expect"] { failures.append("\(where_): got \(got.rawValue)") }
                case "restart":
                    // Persist through bytes, as a real restart would.
                    let bytes = try CanonicalJSON.encode(receiver.state)
                    receiver = SnapshotReceiver(restoring: try JSONDecoder().decode(SnapshotReceiver.State.self, from: bytes))
                case "assert":
                    let state = try JSONValue.parse(CanonicalJSON.encode(receiver.state))
                    let expect = try XCTUnwrapValue(step["expect"]?.object, where_)
                    for (key, value) in expect where state[key] != value {
                        failures.append("\(where_) \(key): got \(state[key] ?? .null), expected \(value)")
                    }
                case let op:
                    throw UnknownOp(ref: where_, op: op ?? "nil")
                }
            }
        }
        return (cases.count, failures)
    }

    // MARK: analysis

    static func analysis(registry: RoomCapabilityRegistry) throws -> (cases: Int, failures: [String]) {
        let file = "vectors/analysis.json"
        let cases = try cases(of: file, kind: "analysis")
        var failures: [String] = []
        for testCase in cases {
            let ref = CaseRef(file: file, id: testCase["id"]?.string ?? "?")
            let doc = try JSONPatch.apply(XCTUnwrapValue(testCase["resultPatch"], ref),
                                          to: RoomFixtures.record(XCTUnwrapValue(testCase["record"]?.string, ref)))
            guard case .analysisResult(let result) = try RoomRecord.decode(doc.data()) else {
                failures.append("\(ref): not an analysis result"); continue
            }
            let capabilities = try JSONDecoder().decode(RoomCapabilities.self,
                                                        from: XCTUnwrapValue(testCase["capabilities"], ref).data())
            let got = ServeResultGate.present(result, capabilities: capabilities, registry: registry,
                                              currentPointEventId: testCase["currentPointEventId"]?.string)
            let shown = try presentationValue(got)
            for (key, value) in try XCTUnwrapValue(testCase["expect"]?.object, ref) where shown[key] != value {
                failures.append("\(ref) \(key): got \(shown[key] ?? .null), expected \(value)")
            }
        }
        return (cases.count, failures)
    }

    // MARK: helpers

    /// The cases of a vector file, after checking its kind (a runner never reads another kind's file).
    static func cases(of file: String, kind: String) throws -> [JSONValue] {
        let doc = try RoomFixtures.json(file)
        guard doc["schemaVersion"]?.string == "jovra.room-fixture.vectors/1", doc["kind"]?.string == kind else {
            throw UnknownOp(ref: CaseRef(file: file, id: "-"), op: "kind \(doc["kind"]?.string ?? "nil")")
        }
        return doc["cases"]?.array ?? []
    }

    static func snapshotRecord(_ doc: JSONValue) throws -> RoomSnapshotRecord {
        guard case .snapshot(let snapshot) = try RoomRecord.decode(doc.data()) else {
            throw UnknownOp(ref: CaseRef(file: "records/room-snapshot.json", id: "-"), op: "not a snapshot")
        }
        return snapshot
    }

    static func reportValue(_ device: JSONValue) throws -> CameraReport {
        CameraReport(deviceId: try XCTUnwrapValue(device["deviceId"]?.string, nil),
                     captureState: try XCTUnwrapValue(CaptureState(rawValue: device["captureState"]?.string ?? ""), nil),
                     lastReportedElapsedMs: try XCTUnwrapValue(device["lastReportedElapsedMs"]?.int, nil))
    }

    static func countsValue(_ counts: RoomCounts) throws -> JSONValue {
        try JSONValue.parse(CanonicalJSON.encode(counts))
    }

    static func rowValue(_ row: StatusRow) -> JSONValue {
        .object([
            "deviceId": .string(row.deviceId), "freshness": .string(row.freshness.rawValue),
            "elapsedMs": .int(row.elapsedMs), "elapsedSource": .string(row.elapsedSource.rawValue),
            "extrapolated": .bool(row.extrapolated), "stale": .bool(row.stale),
            "lastHeardAgeMs": row.lastHeardAgeMs.map(JSONValue.int) ?? .null,
            "mayStillBeRecording": .bool(row.mayStillBeRecording), "captureState": .string(row.captureState.rawValue),
        ])
    }

    static func presentationValue(_ p: AnalysisPresentation) throws -> [String: JSONValue] {
        var out: [String: JSONValue] = [
            "resultId": .string(p.resultId), "scoreEffect": .string(p.scoreEffect), "label": .string(p.label.rawValue),
            "pointEventId": p.pointEventId.map(JSONValue.string) ?? .null, "producedAt": .string(p.producedAt),
            "show": .string(p.show.rawValue), "reason": p.reason.map { .string($0.rawValue) } ?? .null,
            "value": p.value.map(JSONValue.string) ?? .null,
        ]
        if p.show == .current || p.show == .previous {
            out["units"] = p.units.map { .string($0.rawValue) } ?? .null
            out["uncertainty"] = try p.uncertainty.map { try JSONValue.parse(CanonicalJSON.encode($0)) } ?? .null
        }
        return out
    }
}

struct MissingValue: Error, CustomStringConvertible {
    let ref: CaseRef?
    var description: String { "missing or mistyped fixture value at \(ref.map(String.init(describing:)) ?? "?")" }
}

/// Unwraps a fixture value or throws (a malformed fixture fails the test with its case reference).
func XCTUnwrapValue<T>(_ value: T?, _ ref: CaseRef?) throws -> T {
    guard let value else { throw MissingValue(ref: ref) }
    return value
}
