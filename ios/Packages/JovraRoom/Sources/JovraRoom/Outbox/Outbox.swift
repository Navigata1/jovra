/// The issuer's offline outbox, on a phone or a watch (spec/room/reference/jovra_room/ledger.py `Outbox`). Offline
/// commands are drafts: shown as Pending, never applied to the canonical score, and never treated as sent until the
/// host gives a final receipt.
///
/// - **Send age.** Every send recomputes `expiry.ageAtSendMs` from the issuer's monotonic clock, so time spent queued
///   counts towards the TTL: a start request flushed ten minutes later expires. The host cannot see a frozen age, so
///   this is the issuer's conformance rule (D4); the fingerprint excludes the field, so a refreshed retry still matches.
/// - **Epoch guard.** `flush` sends nothing while the outbox's epoch differs from the host's (`reconcile` first), and
///   drafts whose answer is transient (channel, session, epoch) stay queued. Nothing is dropped silently.
/// - **Chains.** Consecutive score drafts are a chain; once one is not Accepted, the later score drafts are held as
///   `Pending/requiresResubmit` and never sent against a revision their author did not see.
///
/// Persist `state` with the drafts; restore it after a process death.
public struct Outbox: Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let command: RoomCommand
        /// The issuer's monotonic time the command was issued at (its send age is measured from here).
        public let issuedAtMonoMs: Int
    }

    public struct State: Codable, Equatable, Sendable {
        public var hostEpoch: Int
        public var knownRevision: Int
        public var queue: [Entry]
        public var receipts: [String: RoomReceipt]
    }

    /// The status a draft has after reconciliation with a new host.
    public struct Reconciled: Equatable, Sendable {
        public let status: ReceiptStatus
        public let reason: RoomReceipt.Reason?
    }

    public private(set) var state: State

    public var hostEpoch: Int { state.hostEpoch }
    public var knownRevision: Int { state.knownRevision }
    /// The drafts still waiting, in issue order.
    public var queue: [Entry] { state.queue }
    /// The latest receipt for every command this issuer has queued, by commandId.
    public var receipts: [String: RoomReceipt] { state.receipts }

    public init(hostEpoch: Int, knownRevision: Int) {
        state = State(hostEpoch: hostEpoch, knownRevision: knownRevision, queue: [], receipts: [:])
    }

    public init(restoring state: State) { self.state = state }

    /// Queues a command issued while offline. `command.expiry.ageAtSendMs` is its age at `nowMonoMs`.
    public mutating func submitOffline(_ command: RoomCommand, nowMonoMs: Int) -> RoomReceipt {
        state.queue.append(Entry(command: command, issuedAtMonoMs: nowMonoMs - command.expiry.ageAtSendMs))
        let receipt = RoomReceipt(for: command, status: .pending, reason: .offlineDraft, revision: nil)
        state.receipts[command.commandId] = receipt
        return receipt
    }

    /// The command as it goes on the wire at `nowMonoMs`, with its send age recomputed.
    public static func outgoing(_ entry: Entry, nowMonoMs: Int) throws(FreshnessInputError) -> RoomCommand {
        let age = nowMonoMs - entry.issuedAtMonoMs
        guard age >= 0 else { throw .negativeAge("ageAtSendMs = \(age): the issuer's monotonic clock went backwards") }
        var command = entry.command
        command.expiry.ageAtSendMs = age
        return command
    }

    /// Sends the queue in order and returns one receipt per draft. Before sending anything every send age is checked,
    /// so a clock that runs backwards sends nothing.
    public mutating func flush<Host: RoomCommandHost>(to host: inout Host, nowMonoMs: Int,
                                                      delivery: DeliveryObservation?,
                                                      peer: AuthenticatedPeer?) throws(FreshnessInputError) -> [RoomReceipt] {
        guard state.hostEpoch == host.hostEpoch else { return [] } // the drafts wait for reconcile()
        let outgoing = try state.queue.map { entry throws(FreshnessInputError) in try Self.outgoing(entry, nowMonoMs: nowMonoMs) }
        var answers: [RoomReceipt] = []
        var keep: [Entry] = []
        var chainBroken = false
        for (entry, command) in zip(state.queue, outgoing) {
            let type = command.payload.type
            let receipt: RoomReceipt
            if chainBroken && type.isScoreCommand {
                receipt = RoomReceipt(for: entry.command, status: .pending, reason: .requiresResubmit, revision: nil)
                keep.append(entry)
            } else {
                receipt = host.submit(command, delivery: delivery, peer: peer)
                if !receipt.isFinal || receipt.isTransient { keep.append(entry) }
                if type.isScoreCommand && receipt.status != .accepted { chainBroken = true }
                if let revision = receipt.canonicalEventRevision { state.knownRevision = revision }
            }
            state.receipts[command.commandId] = receipt
            answers.append(receipt)
        }
        state.queue = keep
        return answers
    }

    /// After a host epoch change: receipts the new host already holds are adopted; capture requests it does not know
    /// expire (never replayed under a new host); other drafts stay Pending until their author resubmits them against
    /// the new epoch and revision.
    public mutating func reconcile(newEpoch: Int, hostReceipts: [String: RoomReceipt]) -> [String: Reconciled] {
        var result: [String: Reconciled] = [:]
        var keep: [Entry] = []
        for entry in state.queue {
            let command = entry.command
            let receipt: RoomReceipt
            if let held = hostReceipts[command.commandId] {
                receipt = held
            } else if command.payload.type.isCaptureRequest {
                receipt = RoomReceipt(for: command, status: .expired, reason: .hostEpochChanged, revision: nil)
            } else {
                receipt = RoomReceipt(for: command, status: .pending, reason: .requiresResubmit, revision: nil)
                keep.append(entry)
            }
            state.receipts[command.commandId] = receipt
            result[command.commandId] = Reconciled(status: receipt.status, reason: receipt.reason)
        }
        state.queue = keep
        state.hostEpoch = newEpoch
        return result
    }
}
