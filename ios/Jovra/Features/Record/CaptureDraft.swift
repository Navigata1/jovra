import Foundation
import JovraCore

/// What "Check camera position" hands the capture route (story 54): the full session setup, plus the
/// singles choices today's capture screen records with when the chosen format is one it can record.
extension SessionSetupDraft {
    init(_ setup: SessionSetup) {
        self.init(kind: SessionKind(setup.mode), captureChoices: CaptureSetupChoices(setup), sessionSetup: setup)
    }
}

extension SessionKind {
    init(_ mode: SessionSetup.Mode) {
        switch mode {
        case .singlesMatch: self = .singlesMatch
        case .doublesMatch: self = .doublesMatch
        case .servePractice: self = .servePractice
        case .strokePractice: self = .strokePractice
        }
    }
}

extension CaptureSetupChoices {
    /// The singles choices for `setup`, or nil when the capture screen could not record it exactly
    /// (doubles, practice, or a format other than one or three tie-break sets with lets). Nil never
    /// substitutes another format: the capture screen then asks again.
    init?(_ setup: SessionSetup) {
        guard setup.mode == .singlesMatch, setup.isReady else { return nil }
        let format = setup.format.format
        guard let match = SinglesMatchFormat.allCases.first(where: { $0.rules(gameScoring: format.gameScoring) == format }) else {
            return nil
        }
        self.init()
        title = SetupCopy.sessionName(setup)
        playerA = setup.me.trimmedName
        playerB = setup.opponent.trimmedName
        self.format = match
        noAd = format.gameScoring == .noAd
        firstServer = setup.effectiveFirstServer == .me ? .a : .b
        nearPlayer = setup.myTeamStartsNear ? .a : .b
    }
}

extension SessionSetupDraft {
    /// Whether today's capture screen can record this draft exactly.
    enum CaptureSupport: Equatable, Sendable {
        case supported
        /// Doubles and practice: capture shows that the mode is not available yet.
        case modeUnavailable
        /// A singles format capture cannot score yet (anything but one or three tie-break sets with
        /// lets): capture says so and never opens its own form with another format.
        case formatUnavailable
    }

    var captureSupport: CaptureSupport {
        guard kind == .singlesMatch else { return .modeUnavailable }
        return sessionSetup != nil && captureChoices == nil ? .formatUnavailable : .supported
    }
}
