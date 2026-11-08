import Foundation
import JovraCore
import JovraRoom

extension Part2Runners {
    /// How the carrier binds a frame to a peer. The live binding hands the ledger the authenticated peer the fixture
    /// names; a mutation can hand it something else (for example the peer the command *claims*).
    typealias PeerBinding = @Sendable (_ authenticated: AuthenticatedPeer?, _ command: RoomCommand,
                             _ members: [String: RoomMember]) -> AuthenticatedPeer?
    static let livePeer: PeerBinding = { peer, _, _ in peer }

    /// How the issuer's outbox puts a draft on the wire: the live path sends it as the outbox produced it; a mutation
    /// can rewrite it (for example freezing `ageAtSendMs` at its offline value). The second argument is the draft's
    /// send age when it was queued offline.
    typealias SendRewrite = @Sendable (_ command: RoomCommand, _ ageWhenQueued: Int?) -> RoomCommand
    static let liveSend: SendRewrite = { command, _ in command }

    // MARK: ledger

    static func ledger(peerBinding: PeerBinding = livePeer) throws -> Outcome {
        let file = "vectors/ledger.json"
        let cases = try VectorRunners.cases(of: file, kind: "ledger")
        var failures: [String] = []
        for testCase in cases {
            let ref = CaseRef(file: file, id: testCase["id"]?.string ?? "?")
            let initial = try XCTUnwrapValue(testCase["initial"], ref)
            var ledger = try makeLedger(initial, ref)
            let members = try membersValue(initial, ref)
            for (index, step) in try XCTUnwrapValue(testCase["steps"]?.array, ref).enumerated() {
                let w = ref.step(index)
                switch step["op"]?.string {
                case "submit":
                    let command = try commandValue(step["command"], w, &failures)
                    let peer = peerBinding(try peerValue(step["peer"]), command, members)
                    let got = ledger.submit(command, delivery: try deliveryValue(step["delivery"]), peer: peer)
                    if let problem = receiptProblem(got) { failures.append("\(w): \(problem)") }
                    let expect = try XCTUnwrapValue(step["expect"], w)
                    let shown = subset(try value(got), expect)
                    if shown != expect { failures.append("\(w): got \(shown), expected \(expect)") }
                case "deliver":
                    let commandId = try XCTUnwrapValue(step["commandId"]?.string, w)
                    let got: RoomReceipt
                    do { got = try ledger.deliver(commandId: commandId) } catch {
                        failures.append("\(w): \(error)")
                        continue
                    }
                    if let problem = receiptProblem(got) { failures.append("\(w): \(problem)") }
                    let expect = try XCTUnwrapValue(step["expect"], w)
                    let results = try value(got)["deviceResults"]
                    if results != expect["deviceResults"] { failures.append("\(w) results: got \(results ?? .null)") }
                    let summary = try value(CaptureFanOutSummary(got))
                    if summary != expect["summary"] { failures.append("\(w) summary: got \(summary)") }
                case "deviceReport":
                    ledger.deviceReported(try XCTUnwrapValue(step["deviceId"]?.string, w),
                                          captureState: try XCTUnwrapValue(CaptureState(rawValue: step["captureState"]?.string ?? ""), w))
                case "restart":
                    ledger = try restartLedger(ledger)
                case "linkLost":
                    let got = JSONValue.object(["commandsIssued": .array(try ledger.roomLinkLost().map(value))])
                    if got != step["expect"] { failures.append("\(w): got \(got)") }
                case "beginEpoch":
                    try ledger.beginEpoch(XCTUnwrapValue(step["newEpoch"]?.int, w))
                case "assert":
                    try assertLedger(ledger, step, w, &failures)
                case let op:
                    throw VectorRunners.UnknownOp(ref: w, op: op ?? "nil")
                }
            }
        }
        return (cases.count, failures)
    }

    // MARK: outbox

    /// A host that applies the issuer's send rewrite before the ledger sees the frame.
    struct RewritingHost: RoomCommandHost {
        var ledger: CommandLedger
        let rewrite: (RoomCommand) -> RoomCommand
        var hostEpoch: Int { ledger.hostEpoch }
        mutating func submit(_ command: RoomCommand, delivery: DeliveryObservation?,
                             peer: AuthenticatedPeer?) -> RoomReceipt {
            ledger.submit(rewrite(command), delivery: delivery, peer: peer)
        }
    }

    static func outbox(send: @escaping SendRewrite = liveSend) throws -> Outcome {
        let file = "vectors/outbox.json"
        let cases = try VectorRunners.cases(of: file, kind: "outbox")
        var failures: [String] = []
        for testCase in cases {
            let ref = CaseRef(file: file, id: testCase["id"]?.string ?? "?")
            let initial = try XCTUnwrapValue(testCase["initial"], ref)
            var ledger = try makeLedger(initial, ref)
            var box = Outbox(hostEpoch: try initial["outboxEpoch"]?.int ?? XCTUnwrapValue(initial["hostEpoch"]?.int, ref),
                             knownRevision: try XCTUnwrapValue(initial["eventRevision"]?.int, ref))
            var queuedAges: [String: Int] = [:]
            for (index, step) in try XCTUnwrapValue(testCase["steps"]?.array, ref).enumerated() {
                let w = ref.step(index)
                func check(_ got: JSONValue, _ expect: JSONValue?) {
                    if got != expect { failures.append("\(w): got \(got), expected \(expect ?? .null)") }
                }
                switch step["op"]?.string {
                case "offline":
                    let command = try commandValue(step["command"], w, &failures)
                    queuedAges[command.commandId] = command.expiry.ageAtSendMs
                    let got = box.submitOffline(command, nowMonoMs: try XCTUnwrapValue(step["nowMonoMs"]?.int, w))
                    if let problem = receiptProblem(got) { failures.append("\(w): \(problem)") }
                    let expect = try XCTUnwrapValue(step["expect"], w)
                    check(subset(try value(got), expect), expect)
                case "hostSubmit":
                    let command = try commandValue(step["command"], w, &failures)
                    let got = ledger.submit(command, delivery: nil, peer: try peerValue(step["peer"]))
                    let expect = try XCTUnwrapValue(step["expect"], w)
                    check(subset(try value(got), expect), expect)
                case "flush":
                    var host = RewritingHost(ledger: ledger) { send($0, queuedAges[$0.commandId]) }
                    let got = try box.flush(to: &host, nowMonoMs: XCTUnwrapValue(step["nowMonoMs"]?.int, w),
                                            delivery: try deliveryValue(step["delivery"]), peer: try peerValue(step["peer"]))
                    ledger = host.ledger
                    for receipt in got { if let problem = receiptProblem(receipt) { failures.append("\(w): \(problem)") } }
                    let expect = try XCTUnwrapValue(step["expect"]?.array, w)
                    if got.count != expect.count {
                        failures.append("\(w): \(got.count) receipts, expected \(expect.count): \(try got.map(value))")
                    } else {
                        check(.array(try zip(got, expect).map { subset(try value($0), $1) }), .array(expect))
                    }
                case "reconcile":
                    let held = try XCTUnwrapValue(step["hostReceipts"]?.object, w).mapValues { doc -> RoomReceipt in
                        guard case .receipt(let r) = try record(doc) else { throw MissingValue(ref: w) }
                        return r.receipt
                    }
                    let got = box.reconcile(newEpoch: try XCTUnwrapValue(step["newEpoch"]?.int, w), hostReceipts: held)
                    check(.object(got.mapValues {
                        .object(["status": .string($0.status.rawValue), "reason": $0.reason.map { .string($0.rawValue) } ?? .null])
                    }), step["expect"])
                    for receipt in box.receipts.values {
                        if let problem = receiptProblem(receipt) { failures.append("\(w): \(problem)") }
                    }
                case "assertQueue":
                    check(.array(box.queue.map { .string($0.command.commandId) }), step["expect"])
                case "assertLedger":
                    try assertLedger(ledger, step, w, &failures)
                case let op:
                    throw VectorRunners.UnknownOp(ref: w, op: op ?? "nil")
                }
            }
        }
        return (cases.count, failures)
    }

    // MARK: helpers

    static func membersValue(_ initial: JSONValue, _ ref: CaseRef) throws -> [String: RoomMember] {
        try XCTUnwrapValue(initial["members"]?.object, ref).mapValues { spec in
            try RoomMember(roles: XCTUnwrapValue(spec["roles"]?.array, ref).map {
                try XCTUnwrapValue(CommandRole(rawValue: $0.string ?? ""), ref)
            }, deviceId: XCTUnwrapValue(spec["deviceId"]?.string, ref),
               watchDeviceIds: (spec["watchDeviceIds"]?.array ?? []).compactMap(\.string))
        }
    }

    static func makeLedger(_ initial: JSONValue, _ ref: CaseRef) throws -> CommandLedger {
        let devices = try XCTUnwrapValue(initial["devices"]?.object, ref).mapValues { d in
            CaptureTarget(captureState: try XCTUnwrapValue(CaptureState(rawValue: d["captureState"]?.string ?? ""), ref),
                          reachable: d["reachable"]?.bool ?? true, acknowledgementLost: d["ackLost"]?.bool ?? false,
                          cameraPermissionGranted: (d["cameraPermission"]?.string ?? "granted") == "granted",
                          foreground: d["foreground"]?.bool ?? true, stopFails: d["stopFault"]?.bool ?? false)
        }
        return CommandLedger(sessionId: try XCTUnwrapValue(initial["sessionId"]?.string, ref),
                             hostEpoch: try XCTUnwrapValue(initial["hostEpoch"]?.int, ref),
                             eventRevision: try XCTUnwrapValue(initial["eventRevision"]?.int, ref),
                             members: try membersValue(initial, ref), devices: devices)
    }

    /// Process death on the host: the ledger is persisted as bytes and read back.
    static func restartLedger(_ ledger: CommandLedger) throws -> CommandLedger {
        let bytes = try CanonicalJSON.encode(ledger.state)
        return CommandLedger(restoring: try JSONDecoder().decode(CommandLedger.State.self, from: bytes))
    }

    /// The command as the fixture writes it, decoded strictly; it must also pass its record rule, except the one
    /// over-long capture TTL the ledger vectors send on purpose.
    static func commandValue(_ doc: JSONValue?, _ ref: CaseRef, _ failures: inout [String]) throws -> RoomCommand {
        let rec = try record(XCTUnwrapValue(doc, ref))
        guard case .command(let command) = rec else { throw MissingValue(ref: ref) }
        do { try rec.checkRules(registry: emptyRegistry) } catch let violation as RoomRuleViolation where violation.code == .ttlTooLong {
        } catch { failures.append("\(ref): command breaks its rule: \(error)") }
        return command
    }

    static func peerValue(_ doc: JSONValue?) throws -> AuthenticatedPeer? {
        guard let doc, doc != .null else { return nil }
        return AuthenticatedPeer(deviceId: try XCTUnwrapValue(doc["deviceId"]?.string, nil))
    }

    static func deliveryValue(_ doc: JSONValue?) throws -> DeliveryObservation? {
        guard let doc, doc != .null else { return nil }
        return DeliveryObservation(transitBounded: doc["transitBounded"]?.bool, transitMs: doc["transitMs"]?.int,
                                   hostHoldMs: doc["hostHoldMs"]?.int)
    }

    static func ledgerStateValue(_ ledger: CommandLedger) throws -> JSONValue {
        .object([
            "eventRevision": .int(ledger.eventRevision), "eventCount": .int(ledger.events.count),
            "markCount": .int(ledger.marks.count), "tally": .object(ledger.tally.mapValues(JSONValue.int)),
            "securityLog": try value(ledger.securityLog),
            "captureStates": .object(ledger.captureStates.mapValues { .string($0.rawValue) }),
            "hostEpoch": .int(ledger.hostEpoch),
        ])
    }

    static func assertLedger(_ ledger: CommandLedger, _ step: JSONValue, _ ref: CaseRef,
                             _ failures: inout [String]) throws {
        let expect = try XCTUnwrapValue(step["expect"], ref)
        let shown = subset(try ledgerStateValue(ledger), expect)
        if shown != expect { failures.append("\(ref): got \(shown), expected \(expect)") }
    }
}
