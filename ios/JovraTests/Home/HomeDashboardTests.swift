import Accessibility
import Foundation
import JovraCore
import Testing
@testable import Jovra

/// Home (S03) from stored session documents. Expected numbers come from the issue's acceptance criteria and the
/// sample library oracle (spec/fixtures/sample/library/library.expected.json), never from the code under test.
@Suite("Home dashboard")
struct HomeDashboardTests {
    private let morning = HomeTestFixtures.october6(hour: 8)

    private func dashboard(_ sessions: [SessionDocument], now: Date? = nil) -> HomeDashboard {
        HomeDashboard.make(sessions: sessions, now: now ?? morning, timeZone: HomeTestFixtures.chicago)
    }

    private func overview(_ dashboard: HomeDashboard) throws -> HomeDashboard.Overview {
        guard case .populated(let overview) = dashboard.content else {
            throw HomeTestFixtures.FixtureError.missing("a populated dashboard")
        }
        return overview
    }

    // MARK: The demo

    @Test("The sample library gives the demo numbers of screen 3")
    func demoNumbers() throws {
        let home = try overview(dashboard(HomeTestFixtures.sampleSessions()))
        #expect(home.isSample)
        #expect(home.sessionCount == 8)
        #expect(home.onCourtSeconds == 6 * 3_600 + 42 * 60)
        #expect(home.firstServes.ratio.n == 40)
        #expect(home.firstServes.ratio.d == 60)
        #expect(home.firstServes.ratio.display == "67%")
        #expect(home.latest.title == "Jon vs Alex")
        #expect(home.latest.scoreline == "6–4 6–3")
        #expect(home.latest.durationSeconds == 54 * 60)
        #expect(home.latest.format == .singles)
        #expect(home.trend.weeks.map { $0.ratio.pct.value } == [48, 55, 63, 67])
        #expect(home.trend.headline?.deltaPoints == 4)
        #expect(home.window.lowerBound == (try CalendarDay("2026-09-09")))
        #expect(home.window.upperBound == (try CalendarDay("2026-10-06")))
    }

    @Test("The demo's latest match has the spec's eight points needing review and asks to finish reviewing")
    func demoNeedsReview() throws {
        let home = dashboard(try HomeTestFixtures.sampleSessions())
        #expect(try overview(home).latest.needsReview == 8)
        #expect(home.nextSteps == [.finishReviewing(sessionID: "b75c57d3-04df-5b4d-b969-32ed5cbfd97a", title: "Jon vs Alex", points: 8)])
    }

    @Test("The demo greets the sample player by name")
    func demoGreeting() throws {
        let home = dashboard(try HomeTestFixtures.sampleSessions())
        #expect(home.playerName == "Jon")
        #expect(HomeGreeting.text(name: home.playerName, at: morning, timeZone: HomeTestFixtures.chicago) == "Good morning, Jon.")
    }

    @Test("Swapping in a modified sample fixture changes every number Home shows")
    func modifiedFixtureChangesNumbers() throws {
        // The library without the Oct 6 match: the newest session is the Oct 4 serve practice, so the window is
        // Sep 7 – Oct 4; the newest match is Jon vs Chris (Sep 28, first serves 38 of 60 in the oracle's week 3);
        // seven sessions and 402 − 54 = 348 minutes remain. Weeks: Sep 7–13 Jon vs Sam 48%, Sep 14–20 Jon vs Alex
        // 55%, Sep 21–27 no match, Sep 28 – Oct 4 Jon vs Chris 63%: 63 − 55 = +8 against the last week shown.
        let sessions = try HomeTestFixtures.sampleSessions().filter { !($0.title == "Jon vs Alex" && ($0.recording.startedAt ?? "").hasPrefix("2026-10-06")) }
        let home = try overview(dashboard(sessions))
        #expect(home.sessionCount == 7)
        #expect(home.onCourtSeconds == 348 * 60)
        #expect(home.firstServes.ratio.n == 38)
        #expect(home.firstServes.ratio.d == 60)
        #expect(home.latest.title == "Serve practice")
        #expect(home.trend.weeks.map { $0.ratio.pct.value } == [48, 55, nil, 63])
        #expect(home.trend.headline?.deltaPoints == 8)
        #expect(home.trend.headline?.priorIndex == 1)
    }

    // MARK: The sample-scope rule

    @Test("One real session beside the samples: only the real session counts and nothing is Sample")
    func realSessionWinsOverSamples() throws {
        let mine = HomeTestFixtures.real(try HomeTestFixtures.jonVsAlex(), id: "mine-1", startedAt: "2026-10-20T22:00:00Z")
        let home = try overview(dashboard(try HomeTestFixtures.sampleSessions() + [mine]))
        #expect(!home.isSample)
        #expect(home.sessionCount == 1)
        #expect(home.onCourtSeconds == 54 * 60)
        #expect(home.latest.id == "mine-1")
        #expect(!home.latest.isSample)
        #expect(home.firstServes.ratio.n == 40)
        #expect(home.trend.state == .tooFewComparable, "one week of matches is not a trend")
        #expect(home.trend.headline == nil)
    }

    // MARK: Empty and no-data states

    @Test("No sessions: the empty state, never zero-filled tiles")
    func freshInstallIsEmpty() {
        let home = dashboard([])
        #expect(home.content == .empty)
        #expect(home.nextSteps.isEmpty)
        #expect(home.playerName == nil)
    }

    @Test("A match with no first serves shows an em dash, never 0%")
    func zeroDenominatorIsAnEmDash() throws {
        var match = HomeTestFixtures.real(try HomeTestFixtures.jonVsAlex(), id: "empty-match", startedAt: "2026-10-20T22:00:00Z")
        match.match?.log = []
        let home = try overview(dashboard([match]))
        #expect(home.firstServes.matchID == "empty-match")
        #expect(home.firstServes.ratio.d == 0)
        #expect(FractionPresentation(ratio: home.firstServes.ratio, provenance: nil).value == "—")
    }

    @Test("Practice only: the first-serves tile has no match yet")
    func practiceOnlyHasNoMatchYet() throws {
        let practice = HomeTestFixtures.real(try HomeTestFixtures.sample(titled: "Serve practice", on: "2026-10-04"),
                                             id: "practice-1", startedAt: "2026-10-20T14:00:00Z")
        let home = try overview(dashboard([practice]))
        #expect(home.firstServes.matchID == nil)
        #expect(FractionPresentation(ratio: home.firstServes.ratio, provenance: nil).value == "—")
        #expect(home.trend.state == .noData)
        #expect(home.latest.format == nil)
    }

    // MARK: Next steps

    @Test("A match with flagged points shows Finish reviewing, opening point review on Needs review")
    func needsReviewShowsFinishReviewing() throws {
        let flagged = HomeTestFixtures.flagging(8, of: HomeTestFixtures.real(
            try HomeTestFixtures.jonVsAlex(), id: "review-me", startedAt: "2026-10-20T22:00:00Z", review: .inProgress))
        let steps = dashboard([flagged]).nextSteps
        #expect(steps.count == 1)
        guard case .finishReviewing(let session, _, let points)? = steps.first else {
            Issue.record("expected Finish reviewing, got \(steps)"); return
        }
        #expect(session == "review-me")
        #expect(points == 8)
        #expect(steps.first?.destination == .fullScreen(.pointReview(SessionID(rawValue: "review-me"), .needsReview)))
    }

    @Test("A reviewed match never asks to be reviewed")
    func completeReviewHasNoStep() throws {
        let done = HomeTestFixtures.flagging(8, of: HomeTestFixtures.real(
            try HomeTestFixtures.jonVsAlex(), id: "done", startedAt: "2026-10-20T22:00:00Z", review: .complete))
        #expect(dashboard([done]).nextSteps.isEmpty)
    }

    @Test("A local-only session shows the back-up row, opening Storage")
    func localOnlyShowsBackUp() throws {
        let local = HomeTestFixtures.real(try HomeTestFixtures.jonVsAlex(), id: "local-1",
                                          startedAt: "2026-10-20T22:00:00Z", archive: .localOnly)
        let steps = dashboard([local]).nextSteps
        #expect(steps == [.backUp(sessionID: "local-1", title: "Jon vs Alex", count: 1)])
        #expect(steps.first?.destination == .push(.profile(.storage)))
    }

    @Test("Sample sessions are never offered for backup")
    func samplesAreNeverBackedUp() throws {
        var sample = try HomeTestFixtures.jonVsAlex()
        sample.archive = SessionArchiveState(state: .localOnly)
        #expect(!dashboard([sample]).nextSteps.contains { if case .backUp = $0 { true } else { false } })
    }

    @Test("A recording saved with gaps or interrupted shows the resume row, opening that session",
          arguments: [SessionOriginalStateState.savedWithGaps, .partial])
    func interruptedShowsResume(state: SessionOriginalStateState) throws {
        let stopped = HomeTestFixtures.real(try HomeTestFixtures.jonVsAlex(), id: "stopped",
                                            startedAt: "2026-10-20T22:00:00Z", original: state, review: .notStarted)
        let steps = dashboard([stopped]).nextSteps
        guard case .resume(let session, _, _)? = steps.first else { Issue.record("expected resume, got \(steps)"); return }
        #expect(session == "stopped")
        #expect(steps.first?.destination == .fullScreen(.replay(ReplayRequest(session: SessionID(rawValue: "stopped"), point: nil, filter: nil))))
    }

    @Test("Next steps are ordered resume, review, back up")
    func nextStepOrder() throws {
        let alex = try HomeTestFixtures.jonVsAlex()
        let stopped = HomeTestFixtures.real(alex, id: "stopped", startedAt: "2026-10-21T22:00:00Z",
                                            original: .savedWithGaps, archive: .localOnly, review: .notStarted)
        let flagged = HomeTestFixtures.flagging(3, of: HomeTestFixtures.real(alex, id: "flagged", startedAt: "2026-10-20T22:00:00Z", review: .inProgress))
        let kinds = dashboard([flagged, stopped]).nextSteps.map(\.id)
        #expect(kinds == ["resume.stopped", "review.flagged", "backUp.stopped"])
    }

    // MARK: Captions and greeting

    @Test("The window caption says Last 4 weeks only when it ends today")
    func windowCaption() throws {
        let window = try CalendarDay("2026-09-09")...CalendarDay("2026-10-06")
        let english = Locale(identifier: "en_US")
        #expect(HomeCopy.windowCaption(window, now: morning, timeZone: HomeTestFixtures.chicago, locale: english) == "Last 4 weeks")
        let later = morning.addingTimeInterval(45 * 86_400)
        #expect(HomeCopy.windowCaption(window, now: later, timeZone: HomeTestFixtures.chicago, locale: english) == "4 weeks to Oct 6")
    }

    @Test("The greeting follows the time of day", arguments: [
        (5, "Good morning, Jon."), (11, "Good morning, Jon."), (12, "Good afternoon, Jon."),
        (17, "Good afternoon, Jon."), (18, "Good evening, Jon."), (4, "Good evening, Jon."),
    ])
    func greetingByHour(hour: Int, expected: String) {
        #expect(HomeGreeting.text(name: "Jon", at: HomeTestFixtures.october6(hour: hour), timeZone: HomeTestFixtures.chicago) == expected)
    }

    @Test("With no name the greeting is just the time of day")
    func greetingWithoutName() {
        #expect(HomeGreeting.text(name: nil, at: morning, timeZone: HomeTestFixtures.chicago) == "Good morning.")
    }

    @Test("The delta reads in percentage points against the prior week")
    func deltaCopy() {
        #expect(HomeCopy.delta(points: 4) == "+4 percentage points vs last week")
        #expect(HomeCopy.delta(points: -1) == "−1 percentage point vs last week")
        #expect(HomeCopy.delta(points: 0) == "No change vs last week")
    }

    // MARK: Audio Graph

    @Test("The trend chart's Audio Graph has one point per shown week with its percentage")
    func audioGraphDescriptor() throws {
        let home = try overview(dashboard(HomeTestFixtures.sampleSessions()))
        let points = HomeTrendAudioGraph.points(for: home.trend)
        #expect(points.map(\.week) == ["Week 1", "Week 2", "Week 3", "Week 4"])
        #expect(points.map(\.percent) == [48, 55, 63, 67])
        #expect(points.last?.fraction == "40 of 60")
        let descriptor = HomeTrendAudioGraph.descriptor(for: home.trend)
        #expect(descriptor.series.count == 1)
        #expect(descriptor.series.first?.dataPoints.count == 4)
        #expect(descriptor.title == "First serves in by week")
    }
}
