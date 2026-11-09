@preconcurrency import AVFoundation
import CoreGraphics
import CoreVideo
import Darwin
import Foundation
import JovraCore
import JovraMedia
import SwiftUI
import Testing
import UIKit
@testable import Jovra

@Suite("Video zoom")
struct VideoZoomTests {
    let size = CGSize(width: 400, height: 225)

    @Test
    func pinchIsClampedToTheSameRangeTheAccessibleLevelsCover() {
        var zoom = VideoZoom()
        zoom.setScale(9, in: size)
        #expect(zoom.scale == VideoZoom.maximum)
        zoom.setScale(0.2, in: size)
        #expect(zoom.scale == VideoZoom.minimum)
        #expect(VideoZoom.levels.first == VideoZoom.minimum && VideoZoom.levels.last == VideoZoom.maximum)
    }

    @Test
    func accessibleStepsVisitEveryLevelAndResumeFromAPinchedScale() {
        var zoom = VideoZoom()
        var visited: [CGFloat] = []
        while zoom.canZoomIn {
            zoom.step(up: true, in: size)
            visited.append(zoom.scale)
        }
        #expect(visited == [1.5, 2, 3, 4])
        zoom.setScale(2.4, in: size)
        zoom.step(up: true, in: size)
        #expect(zoom.scale == 3, "a pinched 240% steps up to the next level, not past it")
        zoom.setScale(2.4, in: size)
        zoom.step(up: false, in: size)
        #expect(zoom.scale == 2)
    }

    @Test
    func panStaysInsideThePictureAndResetClearsIt() {
        var zoom = VideoZoom()
        zoom.pan(to: CGSize(width: 50, height: 50), in: size)
        #expect(zoom.offset == .zero, "nothing to pan at 100%")
        zoom.setScale(2, in: size)
        zoom.pan(to: CGSize(width: 1_000, height: -1_000), in: size)
        #expect(zoom.offset == CGSize(width: 200, height: -112.5))
        zoom.setScale(1.5, in: size)
        #expect(zoom.offset == CGSize(width: 100, height: -56.25), "zooming out pulls the pan back inside")
        zoom.reset()
        #expect(zoom == VideoZoom())
    }
}

@MainActor
@Suite("Frame readout text")
struct FrameReadoutFormatTests {
    let us = Locale(identifier: "en_US")

    @Test
    func timeHasHundredthsAndHoursWhenNeeded() {
        #expect(ReadoutFormat.time(seconds: 46_000.0 / 60, locale: us) == "12:46.67", "the spec’s own example")
        #expect(ReadoutFormat.time(seconds: 0, locale: us) == "0:00.00")
        #expect(ReadoutFormat.time(seconds: 3_723.5, locale: us) == "1:02:03.50")
        #expect(ReadoutFormat.time(seconds: 1.5, locale: Locale(identifier: "de_DE")) == "0:01,50")
    }

    @Test
    func ratesAndFractionalFrameRatesReadNaturally() {
        #expect(PlaybackRate.allCases.map { ReadoutFormat.rate($0, locale: us) } == ["0.25×", "0.5×", "1×", "2×"])
        #expect(ReadoutFormat.fps(.fps240, locale: us) == "240")
        #expect(ReadoutFormat.fps(FrameRate(frames: 30_000, perSeconds: 1_001), locale: us) == "29.97")
    }

    @Test
    func theReadoutAddsTheRateOnlyWhenItIsNot1x() {
        let normal = FrameReadout.text(for: PlaybackReadout(frame: 46_000, frameRate: .fps60, rate: .normal))
        #expect(normal.hasPrefix("f "))
        #expect(normal.contains("60 fps"))
        #expect(!normal.contains("×"))
        let slow = FrameReadout.text(for: PlaybackReadout(frame: 46_000, frameRate: .fps60, rate: .half))
        #expect(slow.hasSuffix("0.5×") || slow.hasSuffix("0,5×"))
        let timeOnly = FrameReadout.text(for: PlaybackReadout(frame: 46_000, frameRate: .fps60, rate: .normal), showsFrames: false)
        #expect(!timeOnly.hasPrefix("f "))
        #expect(timeOnly.hasSuffix("60 fps"))
    }
}

/// The jog strip is the element VoiceOver focuses; an accessibility increment on it (what a VoiceOver swipe up
/// sends) must move the real player exactly one frame and the readout must say so. XCUITest cannot send an
/// adjustable increment on iOS, so this drives the app's own accessibility tree in the hosted test.
@MainActor
@Suite("Jog strip VoiceOver adjust", .serialized)
struct JogStripAccessibilityTests {
    private struct Harness: View {
        let controller: PlaybackController

        var body: some View {
            VStack {
                JogStrip(frame: controller.currentFrame, frameCount: controller.frameCount,
                         framesPerSecond: 60, timeText: ReadoutFormat.time(seconds: controller.readout.seconds),
                         onScrub: { controller.scrub(toFrame: $0) },
                         onScrubEnded: { frame in Task { await controller.endScrub(atFrame: frame) } },
                         onStep: { count in Task { await controller.step(byCount: count) } })
                FrameReadout(readout: controller.readout)
            }
            .padding()
        }
    }

    private struct TimelineHarness: View {
        let controller: PlaybackController

        var body: some View {
            PlaybackTimeline(frame: controller.currentFrame, frameCount: controller.frameCount,
                             currentTimeText: ReadoutFormat.time(seconds: controller.readout.seconds),
                             durationText: ReadoutFormat.time(seconds: 2),
                             onScrub: { controller.scrub(toFrame: $0) },
                             onScrubEnded: controller.finishScrub(atFrame:))
                .padding()
        }
    }

    /// SwiftUI builds its accessibility tree only when an assistive technology asks for it. As the
    /// AccessibilitySnapshot project does for its SwiftUI snapshots, turn application accessibility on for this
    /// test process (test-only; the app never does this).
    private static let accessibilityEnabled: Bool = {
        guard let handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let symbol = dlsym(handle, "_AXSApplicationAccessibilitySetEnabled") else { return false }
        typealias SetEnabled = @convention(c) (Bool) -> Void
        unsafeBitCast(symbol, to: SetEnabled.self)(true)
        return true
    }()

    private struct CounterFixture {
        let url: URL
        let frameCount: Int
    }

    nonisolated private static func frameCounter(_ id: String, filePath: String = #filePath) -> CounterFixture? {
        var root = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        while root.path != "/" && !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/media").path) {
            root.deleteLastPathComponent()
        }
        guard let data = try? Data(contentsOf: root.appendingPathComponent("spec/fixtures/media/frameCounter/\(id).truth.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let media = json["media"] as? [String: Any], let path = media["path"] as? String,
              let video = json["video"] as? [String: Any], let frameCount = video["frameCount"] as? Int else { return nil }
        let url = root.appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: url.path) ? CounterFixture(url: url, frameCount: frameCount) : nil
    }

    /// Independent of the player readout and production decoder: read the centers of the 16 top-row
    /// cells in the committed 640×360 frame-counter fixture. The cells are 40×40, high bit first.
    private func burnedFrameCode(_ pixel: CVPixelBuffer) throws -> Int {
        try #require(CVPixelBufferGetPixelFormatType(pixel) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        try #require(CVPixelBufferLockBaseAddress(pixel, .readOnly) == kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(pixel, .readOnly) }
        try #require(CVPixelBufferGetWidthOfPlane(pixel, 0) == 640 && CVPixelBufferGetHeightOfPlane(pixel, 0) == 360)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixel, 0)
        try #require(stride >= 640)
        let base = try #require(CVPixelBufferGetBaseAddressOfPlane(pixel, 0))
        var code = 0
        for column in 0..<16 {
            let luma = base.load(fromByteOffset: 20 * stride + column * 40 + 20, as: UInt8.self)
            try #require(luma <= 112 || luma >= 144, "a frame-code cell cannot be ambiguous")
            code = (code << 1) | (luma >= 144 ? 1 : 0)
        }
        return code
    }

    private static func identifier(of element: NSObject) -> String? {
        if let id = (element as? UIAccessibilityIdentification)?.accessibilityIdentifier { return id }
        guard element.responds(to: NSSelectorFromString("accessibilityIdentifier")) else { return nil }
        return element.value(forKey: "accessibilityIdentifier") as? String
    }

    private func find(_ identifier: String, in root: NSObject, depth: Int = 0) -> NSObject? {
        if Self.identifier(of: root) == identifier { return root }
        guard depth < 40 else { return nil }
        var children: [Any] = root.accessibilityElements ?? []
        if children.isEmpty {
            let count = root.accessibilityElementCount()
            if count != NSNotFound, count > 0 { children = (0..<count).compactMap { root.accessibilityElement(at: $0) } }
        }
        if let view = root as? UIView { children += view.subviews }
        for case let child as NSObject in children {
            if let found = find(identifier, in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    private func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test(.enabled(if: frameCounter("fc-060") != nil, "Frame-counter fixtures are not rendered"))
    func anIncrementMovesExactlyOneFrameAndTheReadoutSaysSo() async throws {
        // T10's rendered fixture, read from the host's git-ignored cache (media is never committed or bundled).
        let fixture = try #require(Self.frameCounter("fc-060"), "render it: python3 scripts/media/render.py --set frameCounter")
        #expect(Self.accessibilityEnabled)
        let controller = try await PlaybackController.open(url: fixture.url)
        defer { controller.close() }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        window.rootViewController = UIHostingController(rootView: Harness(controller: controller))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let root = try #require(window.rootViewController?.view)
        var jog: NSObject?
        await waitFor { jog = find("playback.jog", in: root); return jog != nil }
        let element = try #require(jog, "the jog strip is one accessibility element")
        #expect(element.accessibilityTraits.contains(.adjustable))
        #expect(element.accessibilityLabel == "Jog strip")

        for expected in [1, 2, 3] {
            element.accessibilityIncrement()
            await waitFor { controller.currentFrame == expected }
            await controller.settle()
            #expect(controller.currentFrame == expected, "one increment, one frame")
        }
        element.accessibilityDecrement()
        await waitFor { controller.currentFrame == 2 }
        #expect(controller.currentFrame == 2)

        var readoutValue: String?
        await waitFor {
            readoutValue = find("playback.readout", in: root)?.accessibilityValue
            return readoutValue?.hasPrefix("f 2 ·") == true
        }
        #expect(readoutValue?.hasPrefix("f 2 ·") == true, "the readout announces the frame: \(readoutValue ?? "nil")")
        await waitFor { find("playback.jog", in: root)?.accessibilityValue?.hasPrefix("Frame 2,") == true }
        #expect(find("playback.jog", in: root)?.accessibilityValue?.hasPrefix("Frame 2,") == true)
    }

    @Test
    func interruptedPanResolvesExactlyOnceAndCannotConsumeTheNextDrag() {
        #expect(!TimelineScrubInteraction.hasHorizontalIntent(.zero))
        #expect(!TimelineScrubInteraction.hasHorizontalIntent(CGPoint(x: 5, y: 22)))
        #expect(!TimelineScrubInteraction.hasHorizontalIntent(CGPoint(x: 15, y: 15)))
        #expect(TimelineScrubInteraction.hasHorizontalIntent(CGPoint(x: -22, y: 5)))
        var pan = TimelineScrubInteraction()
        #expect(pan.change(x: 70, width: 100, frameCount: 101) == 70)
        #expect(pan.cancel() == 70)
        #expect(pan.end(x: 20, width: 100, frameCount: 101) == nil)
        #expect(pan.change(x: 10, width: 100, frameCount: 101) == 10)
        #expect(pan.end(x: 25, width: 100, frameCount: 101) == 25)
        #expect(pan.cancel() == nil)
    }

    @Test(arguments: ["fc-060", "fc-240"])
    func timelineAdjustmentMovesTheDecodedPictureOneFrameAndClampsAtEachEnd(id: String) async throws {
        let fixture = try #require(Self.frameCounter(id), "render it: python3 scripts/media/render.py --set frameCounter")
        let controller = try await PlaybackController.open(url: fixture.url)
        defer { controller.close() }
        #expect(Self.accessibilityEnabled)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        window.rootViewController = UIHostingController(rootView: TimelineHarness(controller: controller))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let root = try #require(window.rootViewController?.view)
        await waitFor { find("playback.timeline", in: root) != nil }
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        controller.player.currentItem?.add(output)

        func verify(_ expected: Int, shouldPause: Bool = false, adjust: (NSObject) -> Void) async throws {
            let element = try #require(find("playback.timeline", in: root))
            #expect(element.accessibilityTraits.contains(.adjustable))
            adjust(element)
            if shouldPause {
                await waitFor { !controller.isPlaying }
                try #require(!controller.isPlaying, "an active accessibility seek must pause and hold its exact target")
            }
            await waitFor { controller.currentFrame == expected }
            await controller.settle()
            #expect(controller.currentFrame == expected)
            let time = controller.player.currentTime()
            var pixel: CVPixelBuffer?
            await waitFor {
                pixel = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil)
                return pixel != nil
            }
            let buffer = try #require(pixel)
            #expect(try burnedFrameCode(buffer) == expected)
            let spokenFrame = "Frame \(JovraFormat.count(expected)),"
            await waitFor { find("playback.timeline", in: root)?.accessibilityValue?.hasPrefix(spokenFrame) == true }
            #expect(find("playback.timeline", in: root)?.accessibilityValue?.hasPrefix(spokenFrame) == true)
        }

        try await verify(0) { $0.accessibilityDecrement() }
        try await verify(1) { $0.accessibilityIncrement() }
        try await verify(2) { $0.accessibilityIncrement() }
        try await verify(1) { $0.accessibilityDecrement() }
        let last = fixture.frameCount - 1
        await controller.seek(toFrame: last)
        await waitFor {
            find("playback.timeline", in: root)?.accessibilityValue?.hasPrefix("Frame \(JovraFormat.count(last)),") == true
        }
        try await verify(last) { $0.accessibilityIncrement() }
        try await verify(last - 1) { $0.accessibilityDecrement() }

        // Start from the beginning so an unpaused control can't pass by naturally reaching the end.
        await controller.seek(toFrame: 0)
        try #require(controller.setRate(.quarter))
        controller.play()
        await waitFor { controller.player.rate > 0 }
        try #require(controller.isPlaying && controller.player.rate > 0)
        var announcedFrame: Int?
        await waitFor {
            let frame = controller.currentFrame
            let prefix = "Frame \(JovraFormat.count(frame)),"
            guard find("playback.timeline", in: root)?.accessibilityValue?.hasPrefix(prefix) == true else { return false }
            announcedFrame = frame
            return true
        }
        let from = try #require(announcedFrame)
        try await verify(from + 1, shouldPause: true) { $0.accessibilityIncrement() }
        #expect(controller.player.rate == 0)

        // An interrupted drag's exact target arrives before the next drag in the same event turn.
        try await verify(12) { _ in
            controller.finishScrub(atFrame: 70)
            controller.scrub(toFrame: 10)
            controller.finishScrub(atFrame: 12)
        }
    }

}
