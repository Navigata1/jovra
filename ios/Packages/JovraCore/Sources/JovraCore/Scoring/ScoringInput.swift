import Foundation

public struct ScoringInput: Codable, Equatable, Sendable {
    public var format: SessionMatchFormat
    public var players: [SessionPlayer]
    public var sides: SessionSides
    public var toss: SessionToss
    public var log: [SessionLogEvent]
    public var resolutionMode: SessionMatchResolutionMode?
    public init(session: SessionDocument) throws {
        guard let match = session.match, let sides = session.sides else { throw ScoringError(.invalidSetup, "match session required") }
        self.init(format: match.format, players: session.players, sides: sides, toss: match.toss, log: match.log, resolutionMode: match.resolutionMode)
    }
    /// Maps unsupported event/mode discriminators to stable domain refusals before replay.
    public static func decode(_ data: Data) throws -> Self {
        do { return try ContractCodec.decode(Self.self, from: data) }
        catch DecodingError.dataCorrupted(let context) {
            if context.debugDescription.contains("Unknown SessionLogEvent discriminator") { throw ScoringError(.unknownEventType, context.codingPath.map(\.stringValue).joined(separator: ".")) }
            if context.codingPath.last?.stringValue == "resolutionMode" { throw ScoringError(.invalidResolutionMode, "resolutionMode") }
            throw DecodingError.dataCorrupted(context)
        }
    }
    public init(format: SessionMatchFormat, players: [SessionPlayer], sides: SessionSides, toss: SessionToss, log: [SessionLogEvent], resolutionMode: SessionMatchResolutionMode? = nil) {
        self.format = format; self.players = players; self.sides = sides; self.toss = toss; self.log = log; self.resolutionMode = resolutionMode
    }
}

public enum ScoringErrorCode: String, Codable, CaseIterable, Sendable {
    case duplicateId, seqNotIncreasing, unknownEventType, voidTargetMissing, voidTargetNotEarlier
    case supersedeTargetMissing, supersedeTypeMismatch, insertTargetMissing, doublesOrderMissing, doublesOrderInvalid, unknownPlayer
    case invalidResolutionMode, overrideTargetMissing, overrideTargetInvalid, overrideMetadataInvalid, receiverOverrideInvalid, overrideRotationInvalid
    case invalidSetup, outcomeMissing
}
public struct ScoringError: Error, Equatable, Sendable {
    public let code: ScoringErrorCode
    public let detail: String
    public init(_ code: ScoringErrorCode, _ detail: String) { self.code = code; self.detail = detail }
}

extension Side {
    var other: Side { self == .a ? .b : .a }
    var timeline: TimelineSideOrNull { self == .a ? .a : .b }
}
extension SideCounts {
    static var zero: Self { Self(A: 0, B: 0) }
    subscript(_ side: Side) -> Int {
        get { side == .a ? A : B }
        set { if side == .a { A = newValue } else { B = newValue } }
    }
}
extension SessionSides { subscript(_ side: Side) -> [String] { side == .a ? A : B } }
extension SessionLogEvent {
    var supersedes: String? {
        switch self {
        case .point(let v): v.supersedes
        case .checkpoint(let v): v.supersedes
        case .penalty(let v): v.supersedes
        case .retirement(let v): v.supersedes
        case .serverOverride(let v): v.supersedes
        case .receiverOverride(let v): v.supersedes
        default: nil
        }
    }
    var insertBefore: String? {
        switch self {
        case .point(let v): v.insertBefore
        case .checkpoint(let v): v.insertBefore
        case .penalty(let v): v.insertBefore
        case .rallyLet(let v): v.insertBefore
        default: nil
        }
    }
}
