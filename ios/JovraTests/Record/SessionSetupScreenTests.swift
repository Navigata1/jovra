import Foundation
import JovraCore
import JovraMedia
import Testing
@testable import Jovra

/// T21: session setup's words, its remembered draft, its storage and pre-flight checks, and the capture
/// route it presents.
@MainActor
struct SessionSetupScreenTests {
    static func readySingles() -> SessionSetup {
        var setup = SessionSetup()
        setup.me.name = "Jon"
        setup.opponent = .init(id: "alex-7", name: "Alex", handedness: .left, backhand: .oneHanded)
        return setup
    }

    static func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("setup.json")
    }

    // MARK: Copy (screen spec §0.2 rule 2)

    /// Every label the format sheet and the scoring row can show, over every preset and every override.
    static var everyFormatLabel: [[String]] {
        var labels: [[String]] = []
        for preset in FormatPreset.allCases {
            for games in [nil] + SessionMatchFormatGameScoring.allCases.map(Optional.some) {
                for sets in [nil] + FormatChoice.SetEnding.allCases.map(Optional.some) {
                    for lets in [nil] + SessionMatchFormatLets.allCases.map(Optional.some) {
                        let choice = FormatChoice(preset: preset, gameScoring: games, setEnding: sets, lets: lets)
                        labels.append(FormatLabel.parts(choice.summary))
                    }
                }
            }
        }
        return labels
    }

    @Test func noFormatLabelUsesTheBareWordAdvantage() {
        let labels = Self.everyFormatLabel
        #expect(labels.count == FormatPreset.allCases.count * 3 * 3 * 3)
        for parts in labels {
            #expect(!parts.contains { $0.trimmingCharacters(in: .whitespaces) == "Advantage" }, "\(parts)")
            #expect(!parts.joined(separator: FormatLabel.separator).contains("Advantage ·"), "\(parts)")
        }
    }

    @Test func gamesReadAdOrNoAdAndSetsReadTieBreakOrAdvantageSet() {
        let games = Set(["Ad", "No-Ad"])
        for parts in Self.everyFormatLabel where parts.count > 1 && !parts[0].hasPrefix("Tie-break only") && parts[0] != "Practice set" {
            #expect(games.contains(parts[1]), "game scoring is the second part: \(parts)")
            let setPart = parts.dropFirst(2).first ?? ""
            let isSetEnding = setPart.hasPrefix("Tie-break at ") || setPart == "Advantage set" || setPart.contains("match tie-break")
                || setPart.contains("-point tie-break at")
            #expect(isSetEnding, "\(parts)")
        }
        #expect(FormatLabel.setEnding(.tiebreak(at: 6)) == "Tie-break at 6–6")
        #expect(FormatLabel.setEnding(.advantageSet) == "Advantage set")
    }

    @Test func theScoringRowAndPresetLinesReadAsSpecified() {
        func line(_ preset: FormatPreset) -> String { FormatLabel.summary(FormatChoice(preset: preset).summary) }
        #expect(line(.clubBestOf3) == "Best of 3 · Ad · Tie-break at 6–6")
        #expect(line(.matchTiebreakThird) == "Best of 3 · Ad · 10-point match tie-break for the third set")
        #expect(line(.noAdMatchTiebreak) == "Best of 3 · No-Ad · 10-point match tie-break for the third set")
        #expect(line(.bestOf5) == "Best of 5 · Ad · 10-point tie-break at 6–6 in the fifth")
        #expect(line(.proSet8) == "Pro set to 8 · Ad · Tie-break at 8–8")
        #expect(line(.shortSets) == "Short sets to 4 · No-Ad · 10-point match tie-break for the third set")
        #expect(line(.tiebreak7) == "Tie-break only to 7")
        #expect(line(.tiebreak10) == "Tie-break only to 10")
        #expect(line(.practiceSet) == "Practice set · No match end")
        var advantage = FormatChoice(preset: .clubBestOf3)
        advantage.setEnding = .advantageSet
        #expect(FormatLabel.summary(advantage.summary) == "Best of 3 · Ad · Advantage set")
    }

    @Test func microphoneOffStatesTheConsequence() {
        #expect(SetupCopy.microphoneDetail(on: false) == "Off: rally detection unavailable; video still records")
    }

    // MARK: Remembered setup (story 55)

    @Test func theLastSetupIsRestoredByTheNextLaunch() {
        let file = Self.tempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let first = SessionSetupStore(file: file)
        #expect(first.setup == SessionSetup(), "a first launch starts from the defaults")
        var chosen = Self.readySingles()
        chosen.format = FormatChoice(preset: .noAdMatchTiebreak, lets: .noLet)
        chosen.firstServer = .opponent
        chosen.myTeamStartsNear = false
        chosen.microphoneOn = false
        chosen.plannedMinutes = 90
        first.setup = chosen
        let relaunched = SessionSetupStore(file: file)
        #expect(relaunched.setup == chosen)
    }

    @Test func anUnreadableDraftStartsFreshInsteadOfBlocking() throws {
        let file = Self.tempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: file)
        #expect(SessionSetupStore(file: file).setup == SessionSetup())
    }

    @Test func choosingAModeSetsItsCameraAngle() {
        let store = SessionSetupStore(file: nil)
        store.select(.strokePractice)
        #expect(store.setup.purpose == .sideOnTechnique)
        store.select(.singlesMatch)
        #expect(store.setup.purpose == .match)
    }

    @Test func deleteAllDataRemovesTheRememberedSetup() async throws {
        let file = Self.tempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        SessionSetupStore(file: file).setup = Self.readySingles()
        #expect(FileManager.default.fileExists(atPath: file.path))
        try await SessionSetupStore.eraser(file: file).erase()
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    // MARK: Capture route (story 54)

    @Test func checkCameraPositionPresentsCaptureWithExactlyTheChosenSetup() throws {
        let router = AppRouter()
        let store = SessionSetupStore(file: nil)
        var setup = Self.readySingles()
        setup.format = FormatChoice(preset: .clubBestOf3, gameScoring: .noAd)
        setup.firstServer = .opponent
        setup.cameraFormatID = "720p30.fixture"
        setup.sessionName = "Club night"
        store.setup = setup
        store.checkCameraPosition(router)
        guard case .capture(let draft?) = router.fullScreenRoute else {
            Issue.record("capture was not presented"); return
        }
        #expect(draft.sessionSetup == setup)
        #expect(draft.kind == .singlesMatch)
        let choices = try #require(draft.captureChoices)
        #expect(choices.title == "Club night")
        #expect(choices.seed.format == setup.format.format, "capture records the chosen format, not a default")
        // The opponent serves first and the recording player's side starts near the camera.
        #expect(choices.seed.toss.firstServer == choices.seed.players[1].id)
        #expect(choices.seed.toss.startingEnds == (try setup.matchSetup()).toss.startingEnds)
        #expect(!router.isTabBarVisible)
    }

    @Test func aSetupWithAProblemIsNeverPresented() {
        let router = AppRouter()
        let store = SessionSetupStore(file: nil)
        store.setup.mode = .doublesMatch
        store.setup.me.name = "Jon"; store.setup.partner.name = "Sam"
        store.setup.opponent.name = "Alex"; store.setup.opponentPartner.name = "Lee"
        store.setup.doublesOrders[0].secondServer = .partner
        #expect(store.setup.problems == [.doublesOrder(set: 0, .serversOnSameTeam)])
        store.checkCameraPosition(router)
        #expect(router.fullScreenRoute == nil)
        #expect(SetupCopy.problem(store.setup.problems[0], in: store.setup).contains("must come from the other team"))
    }

    @Test func captureNeverSubstitutesAFormatItCannotRecord() {
        var setup = Self.readySingles()
        setup.format = FormatChoice(preset: .proSet8)
        let draft = SessionSetupDraft(setup)
        #expect(draft.captureChoices == nil, "a pro set is carried in sessionSetup, never recorded as best of 3")
        #expect(draft.sessionSetup?.format.format.presetId == .proSet8)
        setup.mode = .doublesMatch
        #expect(SessionSetupDraft(setup).kind == .doublesMatch)
    }

    @Test func aDraftRoundTripsThroughStateRestoration() throws {
        let draft = SessionSetupDraft(Self.readySingles())
        let restored = try JSONDecoder().decode(SessionSetupDraft.self, from: JSONEncoder().encode(draft))
        #expect(restored == draft)
    }

    // MARK: Storage and pre-flight (stories 50, N8)

    static let oneHourAt12Mbps = CaptureFormatOption(id: "1080p60.ultraWide", width: 1920, height: 1080, framesPerSecond: 60,
                                                     bitRate: 12_000_000, lens: .ultraWide)

    @Test func theCameraRowStatesTheEstimatedRangeAndFreeSpace() {
        let estimate = StorageEstimator.estimate(bitRate: 12_000_000, plannedSeconds: 3_600, freeBytes: 231_000_000_000)
        #expect(estimate.bytes == 4_590_000_000...6_480_000_000)
        let detail = SetupCopy.storageDetail(estimate)
        #expect(detail.hasPrefix("Estimated space: 4.59 GB–6.48 GB for 1h"), "\(detail)")
        #expect(detail.hasSuffix("231 GB free"), "\(detail)")
        #expect(SetupCopy.cameraValue(Self.oneHourAt12Mbps) == "1080p · 60 fps · Ultra-wide")
    }

    @Test func injectedLowFreeSpaceShowsAWarningChip() throws {
        let low = InjectedDeviceBudget.lowStorage.snapshot
        let estimate = StorageEstimator.estimate(bitRate: CaptureFormatCatalog.fixtureBitRate, plannedSeconds: 3_600, freeBytes: low.freeBytes)
        let storage = try #require(PreflightCheck.checks(budget: low, estimate: estimate).first { $0.kind == .storage })
        #expect(storage.tone == .warn)
        #expect(storage.text == "Room for about 22m")
        #expect(SetupCopy.storageDetail(estimate) == "Not enough space for 1h. About 22m fits.")
        let full = InjectedDeviceBudget.almostFull.snapshot
        let failing = PreflightCheck.storage(StorageEstimator.estimate(bitRate: 12_000_000, plannedSeconds: 3_600, freeBytes: full.freeBytes))
        #expect(failing.tone == .fail)
        #expect(failing.text == "Less than 5 min of space")
        let roomy = PreflightCheck.storage(StorageEstimator.estimate(bitRate: 12_000_000, plannedSeconds: 3_600,
                                                                     freeBytes: InjectedDeviceBudget.roomy.snapshot.freeBytes))
        #expect(roomy.tone == .pass && roomy.text == "Storage ready")
    }

    @Test func batteryAndHeatChipsFollowTheBudget() {
        #expect(PreflightCheck.battery(InjectedDeviceBudget.roomy.snapshot).text == "Battery 78%")
        #expect(PreflightCheck.battery(InjectedDeviceBudget.lowBattery.snapshot).tone == .warn)
        #expect(PreflightCheck.battery(.init(freeBytes: 1, batteryFraction: nil, lowPowerMode: false, thermalState: .nominal)).tone == .unknown)
        #expect(PreflightCheck.heat(InjectedDeviceBudget.roomy.snapshot).text == "Phone cool")
        #expect(PreflightCheck.heat(InjectedDeviceBudget.warm.snapshot).tone == .warn)
    }

    @Test func theStoreEstimatesWithTheChosenPresetAgainstTheBudget() async {
        let store = SessionSetupStore(file: nil)
        let fixture = CaptureFormatOption(id: "720p30.fixture", width: 1280, height: 720, framesPerSecond: 30, bitRate: 4_000_000, lens: .fixture)
        await store.refreshDevice(budget: FakeDeviceBudget(InjectedDeviceBudget.roomy.snapshot)) { [fixture, Self.oneHourAt12Mbps] }
        #expect(store.selectedFormat == fixture, "with nothing chosen the first supported preset is used")
        store.setup.cameraFormatID = Self.oneHourAt12Mbps.id
        #expect(store.storageEstimate?.bytes == 4_590_000_000...6_480_000_000)
        store.setup.cameraFormatID = "4k60.ultraWide"
        #expect(store.selectedFormat == fixture, "a remembered preset this camera lacks falls back to a supported one")
    }
}
