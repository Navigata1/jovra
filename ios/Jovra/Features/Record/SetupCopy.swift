import Foundation
import JovraCore
import JovraMedia

/// Every sentence session setup (S04) shows, in one place so tests and screens share the exact words.
enum SetupCopy {
    // MARK: Screen

    static var title: String { String(localized: "Set up your session", table: "Record", comment: "Screen title") }
    static var subtitle: String {
        String(localized: "Choose a mode and configure your recording settings.", table: "Record", comment: "Screen subtitle")
    }
    static var modesHeading: String { String(localized: "Mode", table: "Record", comment: "Section header over the four session modes") }
    static var settingsHeading: String { String(localized: "Settings", table: "Record", comment: "Section header over the setup rows") }
    static var checkCameraPosition: String { String(localized: "Check camera position", table: "Record", comment: "Primary button") }
    static var importInstead: String { String(localized: "Import a recording instead", table: "Record", comment: "Link under the primary button") }

    // MARK: Modes

    static func modeTitle(_ mode: SessionSetup.Mode) -> String {
        switch mode {
        case .singlesMatch: String(localized: "Singles match", table: "Record", comment: "Session mode")
        case .doublesMatch: String(localized: "Doubles match", table: "Record", comment: "Session mode")
        case .servePractice: String(localized: "Serve practice", table: "Record", comment: "Session mode")
        case .strokePractice: String(localized: "Stroke practice", table: "Record", comment: "Session mode")
        }
    }

    static func modeDescription(_ mode: SessionSetup.Mode) -> String {
        switch mode {
        case .singlesMatch: String(localized: "One vs one. Record the full match and keep score.", table: "Record", comment: "Mode description")
        case .doublesMatch: String(localized: "Two vs two. Keep score with serving and receiving order.", table: "Record", comment: "Mode description")
        case .servePractice:
            String(localized: "Focus on your serve. Log placement and consistency, and estimate speed from marked frames.", table: "Record", comment: "Mode description")
        case .strokePractice: String(localized: "Record groundstrokes, volleys and overheads.", table: "Record", comment: "Mode description")
        }
    }

    static func modeSymbol(_ mode: SessionSetup.Mode) -> String {
        switch mode {
        case .singlesMatch: "rectangle.portrait.split.2x1"
        case .doublesMatch: "person.2"
        case .servePractice: "tennisball"
        case .strokePractice: "tennis.racket"
        }
    }

    // MARK: Rows

    static var playersLabel: String { String(localized: "Players", table: "Record", comment: "Setup row label") }
    static var scoringLabel: String { String(localized: "Scoring", table: "Record", comment: "Setup row label") }
    static var cameraLabel: String { String(localized: "Camera", table: "Record", comment: "Setup row label") }
    static var microphoneLabel: String { String(localized: "Microphone", table: "Record", comment: "Setup row label") }
    static var cameraAngleLabel: String { String(localized: "Camera angle", table: "Record", comment: "Setup row label (practice modes)") }

    static func microphoneDetail(on: Bool) -> String {
        on ? String(localized: "On: used to find rallies", table: "Record", comment: "Microphone row, on")
            : String(localized: "Off: rally detection unavailable; video still records", table: "Record", comment: "Microphone row, off")
    }

    static func purpose(_ purpose: SessionDocumentCapturePurpose) -> String {
        switch purpose {
        case .match: String(localized: "Behind the baseline", table: "Record", comment: "Camera angle")
        case .sideOnTechnique: String(localized: "Side-on (technique)", table: "Record", comment: "Camera angle")
        }
    }

    static func purposeDetail(_ purpose: SessionDocumentCapturePurpose) -> String {
        switch purpose {
        case .match: String(localized: "Framing guidance shows the whole court from behind the baseline.", table: "Record", comment: "Camera angle detail")
        case .sideOnTechnique: String(localized: "Framing guidance shows your swing from the side, for Stroke Lab.", table: "Record", comment: "Camera angle detail")
        }
    }

    // MARK: Players

    static func displayName(_ player: SessionSetup.Player, seat: SetupSeat) -> String {
        let name = player.trimmedName
        guard name.isEmpty else { return name }
        return seatTitle(seat)
    }

    static func seatTitle(_ seat: SetupSeat) -> String {
        switch seat {
        case .me: String(localized: "You", table: "Record", comment: "Seat: the recording player")
        case .partner: String(localized: "Your partner", table: "Record", comment: "Seat")
        case .opponent: String(localized: "Opponent", table: "Record", comment: "Seat")
        case .opponentPartner: String(localized: "Opponent's partner", table: "Record", comment: "Seat")
        }
    }

    /// "Jon · Alex", "Jon & Sam · Alex & Lee", or "Jon" for practice.
    static func playersValue(_ setup: SessionSetup) -> String {
        func name(_ seat: SetupSeat) -> String { displayName(setup[seat], seat: seat) }
        switch setup.mode {
        case .singlesMatch: return String(localized: "\(name(.me)) · \(name(.opponent))", table: "Record", comment: "Players row: me · opponent")
        case .doublesMatch:
            let mine = String(localized: "\(name(.me)) & \(name(.partner))", table: "Record", comment: "A doubles team")
            let theirs = String(localized: "\(name(.opponent)) & \(name(.opponentPartner))", table: "Record", comment: "A doubles team")
            return String(localized: "\(mine) · \(theirs)", table: "Record", comment: "Players row: my team · their team")
        case .servePractice, .strokePractice: return name(.me)
        }
    }

    /// "Right-handed · Left-handed" when every player in play has a known hand; nil otherwise.
    static func handednessDetail(_ setup: SessionSetup) -> String? {
        let hands = setup.seatsInPlay.map { setup[$0].handedness }
        guard setup.mode.isMatch, !hands.contains(.unknown) else { return nil }
        return hands.map(handedness).joined(separator: " · ")
    }

    static func handedness(_ value: SessionPlayerHandedness) -> String {
        switch value {
        case .right: String(localized: "Right-handed", table: "Record", comment: "Handedness")
        case .left: String(localized: "Left-handed", table: "Record", comment: "Handedness")
        case .unknown: String(localized: "Not set", table: "Record", comment: "Handedness or backhand not recorded")
        }
    }

    /// The short segment titles under "Plays": "Right", "Left", "Not set".
    static func hand(_ value: SessionPlayerHandedness) -> String {
        switch value {
        case .right: String(localized: "Right", table: "Record", comment: "Plays right-handed (segment)")
        case .left: String(localized: "Left", table: "Record", comment: "Plays left-handed (segment)")
        case .unknown: String(localized: "Not set", table: "Record", comment: "Handedness or backhand not recorded")
        }
    }

    static func backhand(_ value: SessionPlayerBackhand) -> String {
        switch value {
        case .oneHanded: String(localized: "One-handed", table: "Record", comment: "Backhand")
        case .twoHanded: String(localized: "Two-handed", table: "Record", comment: "Backhand")
        case .unknown: String(localized: "Not set", table: "Record", comment: "Handedness or backhand not recorded")
        }
    }

    /// The session's library title when the player gave none.
    static func defaultSessionName(_ setup: SessionSetup) -> String {
        func name(_ seat: SetupSeat) -> String { displayName(setup[seat], seat: seat) }
        switch setup.mode {
        case .singlesMatch: return String(localized: "\(name(.me)) vs \(name(.opponent))", table: "Record", comment: "Default session name")
        case .doublesMatch:
            return String(localized: "\(name(.me)) & \(name(.partner)) vs \(name(.opponent)) & \(name(.opponentPartner))", table: "Record", comment: "Default session name")
        case .servePractice: return String(localized: "Serve practice", table: "Record", comment: "Default session name")
        case .strokePractice: return String(localized: "Stroke practice", table: "Record", comment: "Default session name")
        }
    }

    static func sessionName(_ setup: SessionSetup) -> String {
        setup.trimmedSessionName.isEmpty ? defaultSessionName(setup) : setup.trimmedSessionName
    }

    // MARK: Problems

    static func problem(_ problem: SetupProblem, in setup: SessionSetup) -> String {
        switch problem {
        case .missingName(let seat):
            switch seat {
            case .me: return String(localized: "Add your name.", table: "Record", comment: "Setup problem")
            case .partner: return String(localized: "Add your partner's name.", table: "Record", comment: "Setup problem")
            case .opponent: return String(localized: "Add your opponent's name.", table: "Record", comment: "Setup problem")
            case .opponentPartner: return String(localized: "Add your opponent's partner's name.", table: "Record", comment: "Setup problem")
            }
        case .nameTooLong(let seat):
            return String(localized: "\(seatTitle(seat))'s name is longer than 60 characters.", table: "Record", comment: "Setup problem")
        case .samePlayerTwice(let seat):
            let name = displayName(setup[seat], seat: seat)
            switch seat {
            case .me: return String(localized: "\(name) is already in this session.", table: "Record", comment: "Setup problem: one person in two seats")
            case .partner: return String(localized: "\(name) is already in this session. Choose someone else as your partner.", table: "Record", comment: "Setup problem: one person in two seats")
            case .opponent: return String(localized: "\(name) is already in this session. Choose someone else as your opponent.", table: "Record", comment: "Setup problem: one person in two seats")
            case .opponentPartner: return String(localized: "\(name) is already in this session. Choose someone else as your opponent's partner.", table: "Record", comment: "Setup problem: one person in two seats")
            }
        case .sessionNameTooLong:
            return String(localized: "The session name is longer than 120 characters.", table: "Record", comment: "Setup problem")
        case .doublesOrder(let set, let issue):
            return doublesProblem(issue, set: set + 1)
        }
    }

    static func doublesProblem(_ issue: DoublesOrderProblem, set: Int) -> String {
        switch issue {
        case .serversOnSameTeam:
            String(localized: "Set \(set): the second server must come from the other team. Service alternates between the teams.", table: "Record", comment: "Doubles order problem")
        case .receiverOnWrongTeam:
            String(localized: "Set \(set): each team's deuce-court receiver must be one of its own players.", table: "Record", comment: "Doubles order problem")
        case .firstServerDiffersFromMatch:
            String(localized: "Set 1 starts with the player who serves first in the match.", table: "Record", comment: "Doubles order problem")
        }
    }

    // MARK: Capture

    /// Capture's card when S04 chose a singles format it cannot score yet (it never substitutes one).
    static var formatNotRecordableTitle: String {
        String(localized: "This match format cannot be recorded yet", table: "Record", comment: "Capture card when the chosen format cannot be scored yet")
    }

    static var formatNotRecordableMessage: String {
        String(localized: "Recording keeps score for one set or best of three tie-break sets, with lets. Close this screen to keep your format. It will not be replaced with another one.", table: "Record", comment: "Capture card when the chosen format cannot be scored yet")
    }

    // MARK: Camera and storage

    static func cameraValue(_ option: CaptureFormatOption) -> String {
        let size = resolution(option)
        let rate = String(localized: "\(option.framesPerSecond) fps", table: "Record", comment: "Frame rate, e.g. 60 fps")
        switch option.lens {
        case .ultraWide:
            return String(localized: "\(size) · \(rate) · Ultra-wide", table: "Record", comment: "Camera preset: size · rate · lens")
        case .wide:
            return String(localized: "\(size) · \(rate) · Wide", table: "Record", comment: "Camera preset: size · rate · lens")
        case .fixture:
            return String(localized: "\(size) · \(rate)", table: "Record", comment: "Camera preset: size · rate")
        }
    }

    static func resolution(_ option: CaptureFormatOption) -> String {
        option.height >= 2160 ? String(localized: "4K", table: "Record", comment: "Resolution")
            : String(localized: "\(String(option.height))p", table: "Record", comment: "Resolution, e.g. 1080p (no digit grouping)")
    }

    static func perMinute(_ option: CaptureFormatOption) -> String {
        String(localized: "\(option.megabytesPerMinute) MB per minute", table: "Record", comment: "Camera sheet: planning size")
    }

    static func bytes(_ value: Int64) -> String {
        value.formatted(.byteCount(style: .file, allowedUnits: [.mb, .gb, .tb], spellsOutZero: false))
    }

    static func plannedLength(minutes: Int) -> String {
        JovraFormat.duration(seconds: Double(minutes * 60))
    }

    /// "Estimated space: 4.6–6.5 GB for 1h · 231 GB free" (always a range, never a constant).
    static func storageDetail(_ estimate: StorageEstimate) -> String {
        let low = bytes(estimate.bytes.lowerBound), high = bytes(estimate.bytes.upperBound)
        let length = plannedLength(minutes: estimate.plannedSeconds / 60)
        let free = bytes(estimate.freeBytes)
        switch estimate.verdict {
        case .ready:
            return String(localized: "Estimated space: \(low)–\(high) for \(length) · \(free) free", table: "Record", comment: "Camera row detail")
        case .lessThanPlanned, .almostFull:
            let fits = JovraFormat.duration(seconds: Double(estimate.fitsSeconds))
            return String(localized: "Not enough space for \(length). About \(fits) fits.", table: "Record", comment: "Camera row detail when space is short")
        }
    }

    static var noSupportedFormat: String {
        String(localized: "No supported camera format", table: "Record", comment: "Camera row when the camera lists nothing JOVRA records")
    }

    static var checkingCamera: String { String(localized: "Checking this camera…", table: "Record", comment: "Camera row while formats load") }
}
