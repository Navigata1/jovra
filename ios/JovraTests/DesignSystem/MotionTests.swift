import SwiftUI
import Testing
@testable import Jovra

/// screens.md §5.3 "Motion and haptics" and user story 360: Reduce Motion replaces animation with none.
@Suite("Motion and haptics")
struct MotionTests {
    @Test("Motion.standard and Motion.reveal resolve to nil with Reduce Motion on")
    func reduceMotionResolvesToNil() {
        #expect(Motion.standard.animation(reduceMotion: true) == nil)
        #expect(Motion.reveal.animation(reduceMotion: true) == nil)
    }

    @Test("without Reduce Motion: standard is a snappy 0.25 s, reveal an ease-out 0.2 s")
    func specTimings() {
        #expect(Motion.standard.animation(reduceMotion: false) == .snappy(duration: 0.25))
        #expect(Motion.reveal.animation(reduceMotion: false) == .easeOut(duration: 0.2))
    }

    @Test("haptics map to the system feedback the spec names")
    func haptics() {
        #expect(Haptic.selection.feedback == .selection)
        #expect(Haptic.success.feedback == .success)
        #expect(Haptic.warning.feedback == .warning)
    }

    @Test("metric tokens match §5.3")
    @MainActor
    func metrics() {
        #expect(HitTarget.capture == 64)
        #expect(HitTarget.stop == 76)
        #expect(Radius.sheet == 28)
        #expect(VideoMetrics.jogStripHeight == 48)
        #expect(VideoMetrics.timelineToJogGap == 16)
        #expect(ReadableColumn.maximumWidth == 720)
    }
}
