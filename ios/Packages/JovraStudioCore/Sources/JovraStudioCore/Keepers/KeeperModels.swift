import Foundation
import JovraCore

// KeeperSelector's inputs and outputs (STU-10, ticket S35). The reference is spec/reference/studio/keepers.py and the
// rules are on spec/studio/modules/keepers.md. All times are integer microseconds on the session (match) clock.

/// A KeeperSelector refusal, with the reference's stable code (the vectors assert the code, never the message).
public struct KeeperRejection: Error, Equatable, Sendable, CustomStringConvertible {
    public enum Code: String, Sendable {
        case badInput, badInterval, duplicateId, unknownProfile, badOptions, unknownKeeper
        /// Footage claimed as this match that cannot be (S35 edits; the record rule's code).
        case brollMisrepresented
    }

    public let code: Code
    public let detail: String

    public init(_ code: Code, _ detail: String) {
        self.code = code
        self.detail = detail
    }

    public var description: String { "\(code.rawValue): \(detail)" }
}

/// One angle of the project as KeeperSelector sees it: its sync piece's state and transform and its render proxy.
public struct KeeperSource: Equatable, Sendable {
    public var sourceId: String
    public var isPrimary: Bool
    /// The sync piece's state; only `reference` and `reviewed` pieces offer a view (the trusted EDL context's rule).
    public var syncState: String
    /// `t_source = (t_session - offsetUs) / rate`.
    public var offsetUs: Int
    public var rate: KeeperSyncRate
    /// The render proxy's frame rate and length.
    public var fps: StudioFrameRate
    public var frameCount: Int

    public init(sourceId: String, isPrimary: Bool, syncState: String, offsetUs: Int, rate: KeeperSyncRate,
                fps: StudioFrameRate, frameCount: Int) {
        self.sourceId = sourceId
        self.isPrimary = isPrimary
        self.syncState = syncState
        self.offsetUs = offsetUs
        self.rate = rate
        self.fps = fps
        self.frameCount = frameCount
    }

    /// The sync states whose pieces a film may cut from.
    public static let usableSyncStates: Set<String> = ["reference", "reviewed"]
}

/// One effective point as a candidate input: from the core fold (`KeeperSelector.points(from:)`) or scored from one
/// angle (`sourceId`). A point without a recorded time cannot be placed.
public struct KeeperPoint: Equatable, Sendable {
    public var eventId: String
    public var index: Int
    public var startUs: Int?
    public var endUs: Int?
    public var rallyLength: Int?
    public var provenance: Provenance
    public var breakPoint: Bool
    public var setPoint: Bool
    public var matchPoint: Bool
    /// The angle the point was scored from, or nil for the core fold's point.
    public var sourceId: String?

    public init(eventId: String, index: Int, startUs: Int?, endUs: Int?, rallyLength: Int? = nil,
                provenance: Provenance, breakPoint: Bool = false, setPoint: Bool = false, matchPoint: Bool = false,
                sourceId: String? = nil) {
        self.eventId = eventId
        self.index = index
        self.startUs = startUs
        self.endUs = endUs
        self.rallyLength = rallyLength
        self.provenance = provenance
        self.breakPoint = breakPoint
        self.setPoint = setPoint
        self.matchPoint = matchPoint
        self.sourceId = sourceId
    }
}

/// A shot (contact) of a point: reviewed, validated and manual shots protect their contact; estimated hits are labelled.
public struct KeeperShot: Equatable, Sendable {
    public var eventId: String
    public var atUs: Int
    public var provenance: Provenance

    public init(eventId: String, atUs: Int, provenance: Provenance) {
        self.eventId = eventId
        self.atUs = atUs
        self.provenance = provenance
    }
}

/// A Mark the player made while recording or reviewing.
public struct KeeperMark: Equatable, Sendable {
    public var markId: String
    public var atUs: Int
    public var note: String?

    public init(markId: String, atUs: Int, note: String? = nil) {
        self.markId = markId
        self.atUs = atUs
        self.note = note
    }
}

/// A lesson clip: on a point (`eventId`) or with its own session window.
public struct KeeperLessonClip: Equatable, Sendable {
    public var clipId: String
    public var lessonId: String
    public var eventId: String?
    public var window: StudioIntervalUs?

    public init(clipId: String, lessonId: String, eventId: String? = nil, window: StudioIntervalUs? = nil) {
        self.clipId = clipId
        self.lessonId = lessonId
        self.eventId = eventId
        self.window = window
    }
}

/// Everything `KeeperSelector.candidates` reads about a project.
public struct KeeperProject: Equatable, Sendable {
    public var sessionDurationUs: Int
    public var sources: [KeeperSource]
    public var points: [KeeperPoint]
    public var shots: [KeeperShot]
    public var marks: [KeeperMark]
    public var lessonClips: [KeeperLessonClip]

    public init(sessionDurationUs: Int, sources: [KeeperSource] = [], points: [KeeperPoint] = [],
                shots: [KeeperShot] = [], marks: [KeeperMark] = [], lessonClips: [KeeperLessonClip] = []) {
        self.sessionDurationUs = sessionDurationUs
        self.sources = sources
        self.points = points
        self.shots = shots
        self.marks = marks
        self.lessonClips = lessonClips
    }
}

/// Where a keeper came from. Output order within one start time is point, Mark, lesson clip.
public enum KeeperOrigin: String, Sendable, CaseIterable {
    case point
    case mark
    case lessonClip = "lesson-clip"

    var order: Int {
        switch self {
        case .point: 0
        case .mark: 1
        case .lessonClip: 2
        }
    }
}

/// One angle's view of a keeper: the keeper's session window in that source's render-proxy frames.
public struct KeeperView: Equatable, Sendable {
    public var sourceId: String
    public var window: StudioFrameWindow
    public var primary: Bool

    public init(sourceId: String, window: StudioFrameWindow, primary: Bool) {
        self.sourceId = sourceId
        self.window = window
        self.primary = primary
    }
}

/// A protected contact. `label` is "Estimated" for an estimated hit that no reviewed contact absorbed.
public struct KeeperContact: Equatable, Sendable {
    public var atUs: Int
    public var provenance: Provenance
    public var label: String?
    public var protect: StudioIntervalUs
    /// The contact's frame on every view of the keeper, in view order.
    public var frames: [KeeperContactFrame]

    public init(atUs: Int, provenance: Provenance, label: String?, protect: StudioIntervalUs,
                frames: [KeeperContactFrame] = []) {
        self.atUs = atUs
        self.provenance = provenance
        self.label = label
        self.protect = protect
        self.frames = frames
    }
}

public struct KeeperContactFrame: Equatable, Sendable {
    public var sourceId: String
    public var frame: Int

    public init(sourceId: String, frame: Int) {
        self.sourceId = sourceId
        self.frame = frame
    }
}

/// The point facts a ranking reads. A Mark or lesson-clip keeper has no point (`index` nil, provenance manual).
public struct KeeperFacts: Equatable, Sendable {
    public var index: Int?
    public var rallyLength: Int?
    /// A rally length a person entered or reviewed; an estimated length is not real.
    public var rallyReal: Bool
    public var breakPoint: Bool
    public var setPoint: Bool
    public var matchPoint: Bool
    public var provenance: Provenance

    public init(index: Int?, rallyLength: Int?, rallyReal: Bool, breakPoint: Bool, setPoint: Bool, matchPoint: Bool,
                provenance: Provenance) {
        self.index = index
        self.rallyLength = rallyLength
        self.rallyReal = rallyReal
        self.breakPoint = breakPoint
        self.setPoint = setPoint
        self.matchPoint = matchPoint
        self.provenance = provenance
    }

    /// A break, set or match point.
    public var isPressure: Bool { breakPoint || setPoint || matchPoint }

    static let noPoint = KeeperFacts(index: nil, rallyLength: nil, rallyReal: false, breakPoint: false, setPoint: false,
                                     matchPoint: false, provenance: .manual)
}

/// A keeper candidate: a moment worth keeping, with its session window, views, contacts and facts.
public struct Keeper: Equatable, Sendable {
    public var keeperId: String
    public var origin: KeeperOrigin
    /// The point event, Mark or lesson clip id this keeper stands for.
    public var eventRefs: [String]
    public var markIds: [String]
    public var lessonClipIds: [String]
    public var session: StudioIntervalUs
    public var views: [KeeperView]
    public var contacts: [KeeperContact]
    public var facts: KeeperFacts
    /// The angles the point was scored from (story 107); empty for the core fold's own point.
    public var seenFrom: [String]

    public init(keeperId: String, origin: KeeperOrigin, eventRefs: [String], markIds: [String] = [],
                lessonClipIds: [String] = [], session: StudioIntervalUs, views: [KeeperView] = [],
                contacts: [KeeperContact] = [], facts: KeeperFacts, seenFrom: [String] = []) {
        self.keeperId = keeperId
        self.origin = origin
        self.eventRefs = eventRefs
        self.markIds = markIds
        self.lessonClipIds = lessonClipIds
        self.session = session
        self.views = views
        self.contacts = contacts
        self.facts = facts
        self.seenFrom = seenFrom
    }
}

/// Something `candidates` could not place, with the reason (`noTime`, `unknownEvent`, `noWindow`).
public struct KeeperUnplaced: Equatable, Sendable {
    public enum Origin: String, Sendable {
        case point, shot
        case lessonClip = "lesson-clip"
    }

    public var id: String
    public var origin: Origin
    public var reason: String

    public init(id: String, origin: Origin, reason: String) {
        self.id = id
        self.origin = origin
        self.reason = reason
    }
}

/// The candidates of a project: keepers in output order (session start, then point, Mark, lesson clip, then id) and
/// what could not be placed.
public struct KeeperCandidates: Equatable, Sendable {
    public var keepers: [Keeper]
    public var unplaced: [KeeperUnplaced]

    public init(keepers: [Keeper], unplaced: [KeeperUnplaced]) {
        self.keepers = keepers
        self.unplaced = unplaced
    }
}

/// A sync transform's playback rate, an exact ratio.
public struct KeeperSyncRate: Equatable, Sendable {
    public var num: Int
    public var den: Int

    public init(num: Int, den: Int) {
        self.num = num
        self.den = den
    }
}

/// Python's `str` order (Unicode code points), so ties break the way the reference breaks them.
func codePointPrecedes(_ a: String, _ b: String) -> Bool {
    a.unicodeScalars.lexicographicallyPrecedes(b.unicodeScalars)
}
