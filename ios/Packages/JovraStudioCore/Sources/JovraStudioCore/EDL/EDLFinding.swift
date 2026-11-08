import Foundation

/// The stable machine codes of the EDL validator. Every raw value is the code `spec/reference/studio/edl.py` raises for
/// the same rule (fixtures assert the code, never the message), plus `stageNotEnabled` from the stage allowlist (SD6b),
/// which is a product gate and not part of the contract.
public enum EDLFindingCode: String, CaseIterable, Codable, Hashable, Sendable {
    // trusted context and binding
    case contextMissing, projectMismatch, staleRevision, unknownProfile, badVersion
    // structure and scalar shapes
    case notObject, unknownField, missingField, badInteger, badIdentifier, badTemplate, badBoolean, badEnum, badHash
    case forbiddenField, forbiddenValue
    // output, grade and sources
    case badFps, badOutput, outputTooLong, durationOutsideProfile, badSources, sourceTooLong, badCoverage, badRate
    case untrustedSource, coverageMismatch, unknownSource, badSourceRole
    // segments
    case tooManySegments, badOp, duplicateId, opNotAllowed, outputGap, badInterval, incompleteCoverage
    case badSpeed, durationMismatch, cleanFrameRule, outsideCoverage, sessionTimeMismatch, badProtected
    case contactUnprotected, chronology, replayWithoutLabel, untrustedReference, kindMismatch
    case labelMissing, replayTooLong, replayBeforeOriginal, replayOutsideOriginal, freezeDuration, cardDuration
    case badTextRefs
    // framing
    case badFraming, framingAspect, upscaleRefused, reframeNotReviewed, badReframe, panTooFast
    // overlays
    case badOverlays, overlayNotAllowed, provenanceNotAllowed, provenanceMismatch, overlayOutsideMoment
    // transitions
    case badTransition, transitionNotAllowed, transitionTooLong, transitionHandle, contactProtected
    case motionInCleanAlternate
    // chapters and windows
    case badChapters, badWindows
    // audio
    case bedCoverage, primaryBedSource, badFade, silenceBindsAudio, fadeTooShort, bedSourceUnavailable, bedClock
    case badAltBed, holdBedNotContinuous, courtBedOffLive, bedSwitchNotAtBoundary, holdBedOverLive, holdBedNotDeadTime
    case liveWithoutCourtAudio, bedOutOfSync, badNarration, consentMissing, disclosureMissing, rightsMissing
    // product stage gate (SD6b), not a contract rule
    case stageNotEnabled
}

/// One reason a plan is refused, with a plain message for the player (story 153). The validator stops at the first
/// contract violation, as the reference does, so a refused plan carries exactly one contract finding; the stage
/// allowlist reports every operation it does not enable.
public struct EDLFinding: Error, Equatable, Hashable, Sendable, CustomStringConvertible {
    public let code: EDLFindingCode
    public let message: String

    public init(_ code: EDLFindingCode, _ message: String) {
        self.code = code
        self.message = message
    }

    public var description: String { "\(code.rawValue): \(message)" }
}

/// The reference's `require(condition, code, message)`. Everything in this folder throws only `EDLFinding`.
@inline(__always)
func require(_ condition: Bool, _ code: EDLFindingCode, _ message: @autoclosure () -> String) throws {
    if !condition { throw EDLFinding(code, message()) }
}
