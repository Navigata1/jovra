import AppKit
import CoreMedia
import JovraBenchmark
@testable import JovraLabelKit
import XCTest

/// Moving between labels and between hit candidates with `.`, `,`, `N` and `P`, and undo around the background
/// candidate search, through the real window. Two of the recordings are written by the test
/// (`SyntheticClip`) because the defects they guard against cannot show on the 60 fps sample video: its frame
/// times are whole 1/90000 s ticks, and one of its frames is shorter than 20 ms.
@MainActor
final class LabelNavigationTests: LabelWindowTestCase {
    private func write(_ shape: SyntheticClip.Shape, named name: String) async throws -> URL {
        let url = scratch.appendingPathComponent(name)
        try await SyntheticClip.write(shape, to: url)
        return url
    }

    /// Presses a key that moves to a label and waits until that label is selected with its own frame on screen.
    private func move(_ key: Character, to label: LabelSelection, _ what: String) async throws {
        press(key)
        XCTAssertEqual(session.selection, label, "\(what) is selected as soon as the key is pressed")
        await session.seekSettled()
        try await wait("\(what) on screen", timeout: 10) { self.session.displayedTime == label.time }
        XCTAssertEqual(session.selection, label, "\(what) is still selected once its frame is up")
    }

    /// Lets a frame that should not come have its chance to arrive.
    private func settle() async throws {
        await session.seekSettled()
        try await Task.sleep(nanoseconds: 300_000_000)
    }

    // MARK: Next and previous label

    func testNextAndPreviousLabelReachEveryLabelWhenFrameTimesAreNotWholeNinetyKilohertzTicks() async throws {
        let shape = SyntheticClip.oddTimeBase
        try await open(try await write(shape, named: "odd-time-base.mov"), findCandidates: false)
        XCTAssertEqual(session.displayedTime, shape.frame(0))

        // Hits on frames 2, 5, 8, 11 and 14, each marked on the frame the stepping lands on.
        let marked: [Int64] = [2, 5, 8, 11, 14]
        var current: Int64 = 0
        for target in marked {
            while current < target {
                press(.right)
                current += 1
                let expected = shape.frame(current)
                try await wait("frame \(current)", timeout: 10) { self.session.displayedTime == expected }
            }
            press("h")
        }
        let hits = marked.map { LabelSelection.hit(time: shape.frame($0), player: .near) }
        XCTAssertEqual(session.labels?.hits.map(\.time), marked.map(shape.frame))
        // The point of this recording: none of these times is a whole number of 1/90000 s ticks.
        XCTAssertTrue(marked.allSatisfy { ($0 * shape.ticksPerFrame * 90_000) % Int64(shape.timescale) != 0 })

        press(.left, option: true)
        try await wait("the first frame again", timeout: 10) { self.session.displayedTime == shape.frame(0) }

        // "." walks every label forward, showing the labelled frame itself, never the one before it.
        for (index, hit) in hits.enumerated() {
            try await move(".", to: hit, "hit \(index + 1)")
            XCTAssertEqual(session.notice?.text, "Hit by the near player at \(hit.time.clock).")
        }
        press(".")
        XCTAssertEqual(session.notice?.text, "No label after this frame.")
        try await settle()
        XCTAssertEqual(session.displayedTime, shape.frame(14))

        // "," walks them back.
        for (index, hit) in hits.enumerated().reversed().dropFirst() {
            try await move(",", to: hit, "hit \(index + 1)")
        }
        press(",")
        XCTAssertEqual(session.notice?.text, "No label before this frame.")

        // Three quick presses move three labels on, without waiting for a frame in between.
        press(".")
        press(".")
        press(".")
        XCTAssertEqual(session.selection, hits[3])
        await session.seekSettled()
        try await wait("the fourth hit on screen", timeout: 10) { self.session.displayedTime == hits[3].time }
        XCTAssertEqual(session.selection, hits[3])

        // Stepping away ends the walk: "." then starts from the frame on screen.
        press(.left)
        try await wait("frame 10", timeout: 10) { self.session.displayedTime == shape.frame(10) }
        try await move(".", to: hits[3], "the hit after frame 10")
        press(.delete)                                              // and Delete acts on the label that was reached
        XCTAssertEqual(session.labels?.hits.map(\.time), [2, 5, 8, 14].map(shape.frame))
    }

    func testALabelTimeGoesToThePlayerExactly() {
        let time = LabelSession.mediaTime(RationalTime(value: 2000, timescale: 29_589))
        XCTAssertEqual(time.value, 2000)
        XCTAssertEqual(time.timescale, 29_589)
        // A time base no CMTime can hold falls back to the nearest nanosecond at or after the time asked for.
        let wide = LabelSession.mediaTime(RationalTime(value: 10_000_000_000, timescale: 30_000_000_000))
        XCTAssertEqual(wide.seconds, 1.0 / 3.0, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(wide.seconds, 1.0 / 3.0)
    }

    func testTwoLabelsOnOneFrameAreBothReached() async throws {
        try await openSample(findCandidates: false)
        press(.right, option: true)
        try await wait("frame 60") { self.session.displayedTime == SampleVideo.frame(60) }
        press("h")                                                  // the serve, and the rally that starts on it
        press("[")
        try await step(10, shift: true, to: 70)
        press("]")
        press(.left, option: true)
        try await wait("frame 10") { self.session.displayedTime == SampleVideo.frame(10) }

        try await move(".", to: .hit(time: SampleVideo.frame(60), player: .near), "the hit")
        try await move(".", to: .rally(start: SampleVideo.frame(60)), "the rally on the same frame")
        try await settle()
        XCTAssertEqual(session.selection, .rally(start: SampleVideo.frame(60)), "a frame arriving late does not take the selection back")
        press(.delete)
        XCTAssertEqual(session.labels?.rallies, [], "Delete removes the rally that was reached")
        XCTAssertEqual(session.labels?.hits.count, 1, "and leaves the hit on the same frame")
    }

    func testWhileTheRecordingPlaysNextLabelStartsFromTheFrameOnScreen() async throws {
        try await openSample(findCandidates: false)
        for frame in [60, 120] as [Int64] {
            press(.right, option: true)
            try await wait("frame \(frame)") { self.session.displayedTime == SampleVideo.frame(frame) }
            press("h")
        }
        press(.left, option: true)
        try await wait("frame 60 again") { self.session.displayedTime == SampleVideo.frame(60) }
        press(.left, option: true)
        try await wait("the first frame again") { self.session.displayedTime == SampleVideo.frame(0) }
        try await move(".", to: .hit(time: SampleVideo.frame(60), player: .near), "the first hit")

        press(.space)                                               // playing on from the first hit, past the second
        XCTAssertTrue(session.isPlaying)
        try await wait("playback to pass the second hit") { self.session.displayedTime > SampleVideo.frame(125) }
        press(".")
        XCTAssertEqual(session.notice?.text, "No label after this frame.", "the walk does not go on from the hit reached before playing")
        press(.space)
        XCTAssertFalse(session.isPlaying)
    }

    // MARK: Next and previous candidate

    func testNextCandidateMovesOnWhenTheSoundStartsLateInItsFrame() async throws {
        let shape = SyntheticClip.thirtyFramesPerSecond
        try await open(try await write(shape, named: "thirty-fps-clicks.mov"))
        let candidates = try XCTUnwrap(session.labels?.hitCandidates?.items)
        XCTAssertEqual(candidates.count, shape.clicks.count, "one candidate per burst: \(candidates.map(\.time.seconds))")
        for (candidate, click) in zip(candidates, shape.clicks) {
            XCTAssertEqual(candidate.time.seconds, click, accuracy: 0.004)
        }
        let frames = candidates.map { shape.frame(shape.frameIndex(at: $0.time.seconds)) }
        XCTAssertEqual(frames, [30, 60, 90, 105].map(shape.frame))
        // The point of this recording: three sounds start more than 20 ms after their frame does.
        XCTAssertEqual(zip(candidates, frames).filter { $0.time.seconds - $1.seconds > 0.020 }.count, 3)

        // N alone walks every candidate; none of them is decided on the way.
        for (index, candidate) in candidates.enumerated() {
            press("n")
            XCTAssertEqual(session.notice?.text, "Candidate at \(candidate.time.clock). H or J confirms it as a hit; R rejects it.")
            await session.seekSettled()
            try await wait("candidate \(index + 1) on screen", timeout: 10) { self.session.displayedTime == frames[index] }
        }
        press("n")
        XCTAssertEqual(session.notice?.text, "No more pending candidates after this frame.")
        try await settle()
        XCTAssertEqual(session.displayedTime, frames[3])
        XCTAssertEqual(session.document?.candidateCounts().pending, 4)

        // P walks them back.
        for index in [2, 1, 0] {
            press("p")
            XCTAssertEqual(session.notice?.text, "Candidate at \(candidates[index].time.clock). H or J confirms it as a hit; R rejects it.")
            await session.seekSettled()
            try await wait("candidate \(index + 1) on screen", timeout: 10) { self.session.displayedTime == frames[index] }
        }
        press("p")
        XCTAssertEqual(session.notice?.text, "No more pending candidates before this frame.")

        // Two quick presses skip a candidate that is left for later; R then rejects the one that was reached.
        press("n")
        press("n")
        await session.seekSettled()
        try await wait("candidate 3 on screen", timeout: 10) { self.session.displayedTime == frames[2] }
        press("r")
        XCTAssertEqual(session.labels?.hitCandidates?.items.map(\.decision), [.pending, .pending, .rejected, .pending])
        await session.seekSettled()
        try await wait("the candidate after the rejected one", timeout: 10) { self.session.displayedTime == frames[3] }

        // After stepping away by hand, N starts from the frame on screen.
        press(.left, option: true)
        try await wait("one second back", timeout: 10) { self.session.displayedTime == shape.frame(75) }
        press("n")
        await session.seekSettled()
        try await wait("the last candidate again", timeout: 10) { self.session.displayedTime == frames[3] }
    }

    // MARK: Undo and the background candidate search

    func testUndoingAnEditMadeWhileTheToolWasListeningKeepsTheCandidates() async throws {
        try await open(try SampleVideo.url(), autosave: true, settled: false)
        XCTAssertEqual(session.candidateSearch, .searching, "the labeller starts while the tool is still listening")
        XCTAssertNil(session.labels?.hitCandidates)
        press("h")                                                  // undone after the candidates arrive
        press("j")
        press(.character("z"), command: true)                       // undone before they arrive: redone after
        XCTAssertEqual(session.labels?.hits.count, 1)
        XCTAssertEqual(session.candidateSearch, .searching)

        await session.candidatesSettled()
        XCTAssertEqual(session.candidateSearch, .found(7))
        XCTAssertEqual(session.labels?.hitCandidates?.items.count, 7)

        press(.character("z"), command: true)
        XCTAssertEqual(session.labels?.hits, [])
        XCTAssertEqual(session.labels?.hitCandidates?.items.count, 7, "undo takes back the hit, not the candidates")
        XCTAssertEqual(session.document?.candidateCounts().pending, 7)
        XCTAssertEqual(try savedLabels().hitCandidates?.items.count, 7, "and the label file keeps them")

        press("n")
        XCTAssertEqual(session.notice?.text, "Candidate at 0:01.500. H or J confirms it as a hit; R rejects it.")
        await session.seekSettled()
        try await wait("the first candidate's frame") { self.session.displayedTime == SampleVideo.frame(90) }

        press(.character("z"), shift: true, command: true)
        press(.character("z"), shift: true, command: true)
        XCTAssertEqual(session.labels?.hits.map(\.player), [.far, .near])
        XCTAssertEqual(session.labels?.hitCandidates?.items.count, 7, "redo brings back the hits, with the candidates")
        XCTAssertFalse(session.canRedo)
        XCTAssertEqual(try savedLabels(), session.document?.stored)
    }
}
