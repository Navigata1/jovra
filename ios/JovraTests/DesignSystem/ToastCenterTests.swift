import Testing
@testable import Jovra

/// screens.md §5.2: a Toast is announced to VoiceOver and lasts 4 s; an UndoBar lasts 8 s.
@MainActor
@Suite("Toast and UndoBar")
struct ToastCenterTests {
    final class AnnouncerSpy: AccessibilityAnnouncing {
        var announced: [String] = []
        func announce(_ message: String) { announced.append(message) }
    }

    @Test("showing a toast posts a VoiceOver announcement with its text")
    func announces() {
        let spy = AnnouncerSpy()
        let center = ToastCenter(announcer: spy, sleep: { _ in })
        center.show("Score updated for points 43–124")
        #expect(spy.announced == ["Score updated for points 43–124"])
        #expect(center.current?.text == "Score updated for points 43–124")
        #expect(center.current?.duration == .seconds(4))
    }

    @Test("a toast dismisses itself when its time is up")
    func expires() async {
        let center = ToastCenter(announcer: AnnouncerSpy(), sleep: { _ in })
        center.show("Drawing saved")
        await center.expiry?.value
        #expect(center.current == nil)
    }

    @Test("an UndoBar lasts 8 s, announces, and Undo runs its action once and dismisses")
    func undo() {
        let spy = AnnouncerSpy()
        let center = ToastCenter(announcer: spy, sleep: { _ in })
        var undone = 0
        center.show("Moved to Recently deleted", undo: { undone += 1 })
        #expect(center.current?.duration == .seconds(8))
        #expect(center.current?.canUndo == true)
        center.undo()
        center.undo()
        #expect(undone == 1)
        #expect(center.current == nil)
        #expect(spy.announced == ["Moved to Recently deleted"])
    }
}
