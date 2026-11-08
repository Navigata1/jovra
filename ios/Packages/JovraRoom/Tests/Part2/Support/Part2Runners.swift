import Foundation
import JovraCore
import JovraRoom

/// Runs the Part 2 vector kinds (W02, #271) against the package, mirroring scripts/spec/validate_room.py, and returns
/// one message per failing case. As in Part 1, each runner takes the seam under test as a parameter so the mutation
/// tests can hand it a deliberately broken one and prove the fixtures catch it.
enum Part2Runners {
    typealias Outcome = (cases: Int, failures: [String])

    // MARK: watch-sample

    static func watchSample() throws -> Outcome {
        let file = "vectors/watch-sample.json"
        let cases = try VectorRunners.cases(of: file, kind: "watch-sample")
        var failures: [String] = []
        for testCase in cases {
            let ref = CaseRef(file: file, id: testCase["id"]?.string ?? "?")
            let expect = try XCTUnwrapValue(testCase["expect"], ref)
            let summary: HealthSummary
            switch testCase["source"]?.string {
            case "design":
                summary = try designSampleSummary()
                for (deviceId, elapsed) in try XCTUnwrapValue(expect["frozenElapsedMs"]?.object, ref) {
                    let row = summary.rows.first { $0.deviceId == deviceId }
                    if row.map({ JSONValue.int($0.elapsedMs) }) != elapsed {
                        failures.append("\(ref) frozen \(deviceId): got \(row?.elapsedMs ?? -1)")
                    }
                }
            case "bridge":
                let doc = try JSONPatch.apply(XCTUnwrapValue(testCase["bridgePatch"], ref),
                                              to: RoomFixtures.record("watch-bridge.sample"))
                summary = try HealthSummary.watch(bridgeRecord(doc),
                                                  nowMonoMs: XCTUnwrapValue(testCase["nowMonoMs"]?.int, ref),
                                                  currentBaselineId: XCTUnwrapValue(testCase["currentBaselineId"]?.string, ref))
            case let source:
                throw VectorRunners.UnknownOp(ref: ref, op: "source \(source ?? "nil")")
            }
            let freshness = JSONValue.object(Dictionary(uniqueKeysWithValues: summary.rows.map {
                ($0.deviceId, JSONValue.string($0.freshness.rawValue))
            }))
            if freshness != expect["freshness"] { failures.append("\(ref) freshness: got \(freshness)") }
            if try VectorRunners.countsValue(summary.counts) != expect["counts"] {
                failures.append("\(ref) counts: got \(summary.counts)")
            }
        }
        return (cases.count, failures)
    }

    /// The unchanged design handoff sample (it predates the bridge record): its fixture-only transport observation and
    /// the bridge's ages, read at the instant of acceptance.
    static func designSampleSummary() throws -> HealthSummary {
        let url = RoomFixtures.repositoryRoot.appendingPathComponent("design-reference/adaptive/brief/watch-snapshot.sample.json")
        let raw = try JSONValue.parse(Data(contentsOf: url))
        let observation = try XCTUnwrapValue(raw["transportObservation"], nil)
        let devices = try XCTUnwrapValue(raw["devices"]?.array, nil)
        let rows = try devices.map { device -> (report: CameraReport, freshness: Freshness, ageMs: Int?) in
            let freshness = try FreshnessRule.classify(
                senderAgeMs: XCTUnwrapValue(device["ageAtBridgeMs"]?.int, nil), sinceAcceptMs: 0,
                transitBounded: XCTUnwrapValue(observation["transitBounded"]?.bool, nil), transitMs: 0,
                baselineValid: XCTUnwrapValue(observation["baselineValid"]?.bool, nil))
            return (try VectorRunners.reportValue(device), freshness, nil)
        }
        return try HealthSummary(rows: rows, enrolled: devices.compactMap { $0["deviceId"]?.string })
    }

    // MARK: bridge

    typealias BridgeAccept = (inout BridgeReceiver, WatchBridgeSnapshot) -> BridgeVerdict
    typealias BridgeRestart = (BridgeReceiver) throws -> BridgeReceiver

    static func liveAccept(_ receiver: inout BridgeReceiver, _ env: WatchBridgeSnapshot) -> BridgeVerdict {
        receiver.accept(env)
    }

    /// A watch restart: the marks are persisted as bytes and read back, as a real relaunch would.
    static func liveRestart(_ receiver: BridgeReceiver) throws -> BridgeReceiver {
        let bytes = try CanonicalJSON.encode(receiver.state)
        return BridgeReceiver(restoring: try JSONDecoder().decode(BridgeReceiver.State.self, from: bytes))
    }

    static func bridge(accept: BridgeAccept = liveAccept, restart: BridgeRestart = liveRestart) throws -> Outcome {
        let file = "vectors/bridge.json"
        let cases = try VectorRunners.cases(of: file, kind: "bridge")
        let base = try RoomFixtures.record("watch-bridge.sample")
        var failures: [String] = []
        for testCase in cases {
            let ref = CaseRef(file: file, id: testCase["id"]?.string ?? "?")
            var receiver = BridgeReceiver(pairedPhoneId: try XCTUnwrapValue(testCase["pairedPhoneId"]?.string, ref))
            for (index, step) in try XCTUnwrapValue(testCase["steps"]?.array, ref).enumerated() {
                let where_ = ref.step(index)
                switch step["op"]?.string {
                case "accept":
                    let env = try bridgeRecord(JSONPatch.apply(XCTUnwrapValue(step["bridgePatch"], where_), to: base))
                    let got = accept(&receiver, env).rawValue
                    if .string(got) != step["expect"] { failures.append("\(where_): got \(got)") }
                case "restart":
                    receiver = try restart(receiver)
                case let op:
                    throw VectorRunners.UnknownOp(ref: where_, op: op ?? "nil")
                }
            }
        }
        return (cases.count, failures)
    }

    // MARK: alerts

    static func alerts() throws -> Outcome {
        let file = "vectors/alerts.json"
        let cases = try VectorRunners.cases(of: file, kind: "alerts")
        var failures: [String] = []
        for testCase in cases {
            let ref = CaseRef(file: file, id: testCase["id"]?.string ?? "?")
            var policy = AlertPolicy()
            for (index, step) in try XCTUnwrapValue(testCase["steps"]?.array, ref).enumerated() {
                let where_ = ref.step(index)
                let t = try XCTUnwrapValue(step["t"]?.int, where_)
                switch step["op"]?.string {
                case "status":
                    policy.status(at: t, deviceId: try XCTUnwrapValue(step["deviceId"]?.string, where_),
                                  freshness: try XCTUnwrapValue(Freshness(rawValue: step["freshness"]?.string ?? ""), where_),
                                  captureState: try XCTUnwrapValue(CaptureState(rawValue: step["captureState"]?.string ?? ""), where_))
                case "tick": policy.tick(at: t)
                case "point": policy.pointAccepted(at: t)
                case "own":
                    let kind = try XCTUnwrapValue(WatchBridgeSnapshot.Alert.Kind(rawValue: step["kind"]?.string ?? ""), where_)
                    try policy.own(at: t, kind: kind, deviceId: step["deviceId"]?.string)
                case "ack": policy.acknowledge(at: t, alertId: try XCTUnwrapValue(step["alertId"]?.string, where_))
                case let op: throw VectorRunners.UnknownOp(ref: where_, op: op ?? "nil")
                }
            }
            let expect = try XCTUnwrapValue(testCase["expect"], ref)
            let events = JSONValue.array(policy.events.map(eventValue))
            if events != expect["events"] { failures.append("\(ref) events: got \(events)") }
            if !policy.commandsIssued.isEmpty || expect["commandsIssued"] != .array([]) { failures.append("\(ref) commands") }
        }
        return (cases.count, failures)
    }

    static func eventValue(_ event: AlertEvent) -> JSONValue {
        func alert(_ t: Int, _ name: String, _ a: RaisedAlert) -> JSONValue {
            .object(["t": .int(t), "event": .string(name), "alertId": .string(a.alertId), "kind": .string(a.kind.rawValue),
                     "deviceId": a.deviceId.map(JSONValue.string) ?? .null, "severity": .string(a.severity.rawValue)])
        }
        switch event {
        case .raise(let t, let a): return alert(t, "raise", a)
        case .clear(let t, let a): return alert(t, "clear", a)
        case .ack(let t, let a): return alert(t, "ack", a)
        case .haptic(let t, let ids, let pattern):
            return .object(["t": .int(t), "event": .string("haptic"), "alertIds": .array(ids.map(JSONValue.string)),
                            "pattern": .string(pattern.rawValue)])
        }
    }

    // MARK: helpers

    static func value<T: Encodable>(_ v: T) throws -> JSONValue { try JSONValue.parse(CanonicalJSON.encode(v)) }

    /// The reference's `subset`: the actual document restricted to the expected keys (a missing key reads as null).
    static func subset(_ actual: JSONValue, _ expected: JSONValue) -> JSONValue {
        .object(Dictionary(uniqueKeysWithValues: (expected.object ?? [:]).keys.map { ($0, actual[$0] ?? .null) }))
    }

    static func record(_ doc: JSONValue) throws -> RoomRecord { try RoomRecord.decode(doc.data()) }

    static func bridgeRecord(_ doc: JSONValue) throws -> WatchBridgeSnapshot {
        guard case .watchBridge(let env) = try record(doc) else { throw MissingValue(ref: nil) }
        return env
    }

    static let emptyRegistry = RoomCapabilityRegistry(statuses: [:])

    /// A produced receipt must be schema-valid and pass its record rule, as validate_room.py `_check_receipt`.
    static func receiptProblem(_ receipt: RoomReceipt) -> String? {
        do {
            try record(value(receipt)).checkRules(registry: emptyRegistry)
            return nil
        } catch {
            return "receipt \(receipt.commandId) invalid: \(error)"
        }
    }
}
