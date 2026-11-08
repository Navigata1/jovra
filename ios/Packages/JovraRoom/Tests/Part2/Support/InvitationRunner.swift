import Foundation
import JovraCore
import JovraRoom

extension Part2Runners {
    /// vectors/invitation.json: the host's join exchange, the joiner's checks and strict QR decoding. After every case
    /// the host log must hold no token, proof or nonce.
    static func invitation() throws -> Outcome {
        let file = "vectors/invitation.json"
        let cases = try VectorRunners.cases(of: file, kind: "invitation")
        let doc = try RoomFixtures.json(file)
        let secrets = try XCTUnwrapValue(doc["secrets"], nil)
        let tokens = try stringMap(secrets["tokens"])
        let nonces = try stringMap(secrets["nonces"])
        let joinRequest = try RoomFixtures.record("join-request")
        var failures: [String] = []
        for testCase in cases {
            let ref = CaseRef(file: file, id: testCase["id"]?.string ?? "?")
            let initial = try XCTUnwrapValue(testCase["initial"], ref)
            let records = try XCTUnwrapValue(initial["records"]?.array, ref).map { path -> RoomInvitation in
                guard case .invitation(let r) = try record(RoomFixtures.record(XCTUnwrapValue(path.string, ref))) else {
                    throw MissingValue(ref: ref)
                }
                return r
            }
            var host = HostInvitations(sessionId: try XCTUnwrapValue(initial["sessionId"]?.string, ref),
                                       hostEpoch: try XCTUnwrapValue(initial["hostEpoch"]?.int, ref),
                                       hostKey: try XCTUnwrapValue(initial["hostKey"]?.string, ref),
                                       records: records, tokens: tokens, nonces: nonces,
                                       members: try stringMap(initial["members"]))
            for (index, step) in try XCTUnwrapValue(testCase["steps"]?.array, ref).enumerated() {
                let w = ref.step(index)
                func check(_ got: JSONValue) {
                    if got != step["expect"] { failures.append("\(w): got \(got), expected \(step["expect"] ?? .null)") }
                }
                switch step["op"]?.string {
                case "join":
                    guard case .joinRequest(let request) = try record(JSONPatch.apply(
                        XCTUnwrapValue(step["requestPatch"], w), to: joinRequest)) else { throw MissingValue(ref: w) }
                    let hostNonce = try XCTUnwrapValue(step["hostNonce"]?.string, w)
                    check(outcomeValue(host.validateJoin(request, now: try timestamp(step["now"], w), hostNonce: hostNonce)))
                    // The challenge the host would send is a schema-valid record.
                    _ = try record(nonceFrame("join-challenge", "hostNonce", hostNonce, request.inviteId))
                case "reveal":
                    let inviteId = try XCTUnwrapValue(step["inviteId"]?.string, w)
                    let guestNonce = try XCTUnwrapValue(step["guestNonce"]?.string, w)
                    _ = try record(nonceFrame("join-reveal", "guestNonce", guestNonce, inviteId))
                    check(outcomeValue(host.reveal(inviteId: inviteId, guestNonce: guestNonce)))
                case "approve":
                    check(outcomeValue(host.approve(inviteId: try XCTUnwrapValue(step["inviteId"]?.string, w),
                                                    codesMatchConfirmed: try XCTUnwrapValue(step["confirmed"]?.bool, w),
                                                    now: try timestamp(step["now"], w))))
                case "assertRecord":
                    let current = try XCTUnwrapValue(host.record(XCTUnwrapValue(step["inviteId"]?.string, w)), w)
                    let encoded = try value(current)
                    check(subset(encoded, try XCTUnwrapValue(step["expect"], w)))
                    do { try record(encoded).checkRules(registry: emptyRegistry) } catch {
                        failures.append("\(w): the record broke its schema or rule: \(error)")
                    }
                case "transferHost":
                    let revoked = host.transferHost(newEpoch: try XCTUnwrapValue(step["newEpoch"]?.int, w),
                                                    newHostKey: try XCTUnwrapValue(step["newHostKey"]?.string, w))
                    check(.object(["revoked": .array(revoked.map(JSONValue.string))]))
                case "lookup":
                    let got = host.lookup(displayCode: try XCTUnwrapValue(step["code"]?.string, w),
                                          source: try XCTUnwrapValue(step["source"]?.string, w), now: try timestamp(step["now"], w))
                    check(.object(["result": .string(got.result.rawValue), "inviteId": got.inviteId.map(JSONValue.string) ?? .null,
                                   "authenticates": .bool(got.authenticates)]))
                case "joinerVerify":
                    guard case .invitationPayload(let payload) = try record(JSONPatch.apply(
                        XCTUnwrapValue(step["payloadPatch"], w), to: RoomFixtures.record("invitation-payload"))) else {
                        throw MissingValue(ref: w)
                    }
                    check(.string(InvitationJoiner.verify(payload, observedHostKey: try XCTUnwrapValue(step["observedHostKey"]?.string, w)).rawValue))
                case "checkResolved":
                    check(.string(InvitationJoiner.checkResolvedEndpoint(address: try XCTUnwrapValue(step["address"]?.string, w),
                                                                         port: try XCTUnwrapValue(step["port"]?.int, w)).rawValue))
                case "decodeQr":
                    if step["fromPayload"]?.bool == true {
                        guard case .invitationPayload(let payload) = try record(RoomFixtures.record("invitation-payload")) else {
                            throw MissingValue(ref: w)
                        }
                        check(.object(["roundTrip": .bool(try InvitationQR.decode(InvitationQR.encode(payload)) == payload)]))
                    } else {
                        let text = try XCTUnwrapValue(step["text"]?.string, w)
                        do throws(InvitationQRError) {
                            _ = try InvitationQR.decodeCanonicalBytes(text)
                            check(.object(["decoded": .bool(true)]))
                        } catch {
                            check(.object(["error": .string(error.code)]))
                        }
                    }
                case let op:
                    throw VectorRunners.UnknownOp(ref: w, op: op ?? "nil")
                }
            }
            let log = String(decoding: try CanonicalJSON.encode(host.log), as: UTF8.self)
            let secretValues = Array(tokens.values) + Array(nonces.values)
                + [joinRequest["proof"]?.string, try RoomFixtures.record("join-reveal")["guestNonce"]?.string].compactMap { $0 }
            if secretValues.contains(where: { log.contains($0) }) { failures.append("\(ref): host log contains a secret") }
        }
        return (cases.count, failures)
    }

    static func outcomeValue(_ o: JoinOutcome) -> JSONValue {
        .object([
            "result": .string(o.result.rawValue), "code": o.code.map { .string($0.rawValue) } ?? .null,
            "grants": .array(o.grants.map(JSONValue.string)),
            "verificationCode": o.verificationCode.map(JSONValue.string) ?? .null,
            "hostNonce": o.hostNonce.map(JSONValue.string) ?? .null, "deviceId": o.deviceId.map(JSONValue.string) ?? .null,
        ])
    }

    private static func nonceFrame(_ name: String, _ key: String, _ nonce: String, _ inviteId: String) throws -> JSONValue {
        guard case .object(var frame) = try RoomFixtures.record(name) else { throw MissingValue(ref: nil) }
        frame[key] = .string(nonce)
        frame["inviteId"] = .string(inviteId)
        return .object(frame)
    }

    static func timestamp(_ value: JSONValue?, _ ref: CaseRef) throws -> RoomTimestamp {
        try XCTUnwrapValue(value?.string.flatMap(RoomTimestamp.init), ref)
    }

    static func stringMap(_ value: JSONValue?) throws -> [String: String] {
        try XCTUnwrapValue(value?.object, nil).mapValues { try XCTUnwrapValue($0.string, nil) }
    }
}
