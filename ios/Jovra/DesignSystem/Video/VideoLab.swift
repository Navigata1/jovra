// l10n-lint: ignore-file (DEBUG-only video lab for UI tests and screenshots; absent from release builds)
#if DEBUG
import JovraCore
import JovraMedia
import SwiftUI

/// The playback gallery: the frame-counter fixtures and the synthetic sample match on the shared player,
/// surface, timeline, jog strip and transport. `JOVRA_VIDEO_LAB=<source>` (fc-060, fc-240, sample, missing)
/// replaces the app's root with it (see `CoreComponentsGalleryHarness`); simulator only for the counters, which are
/// read from `JOVRA_FRAME_COUNTER_DIR`. Every clip here is synthetic and badged.
struct VideoLab: View {
    enum Source: String, CaseIterable, Identifiable, Hashable {
        case fc060 = "fc-060", fc240 = "fc-240", sample, missing
        var id: String { rawValue }

        var title: String {
            switch self {
            case .fc060: "Counter 60 fps"
            case .fc240: "Counter 240 fps"
            case .sample: "Sample match"
            case .missing: "Missing file"
            }
        }

        /// The frame counters are T10's rendered fixtures, never committed or bundled (media stays in the
        /// git-ignored cache): the simulator reads them from the folder the test passes in
        /// `JOVRA_FRAME_COUNTER_DIR`. The sample match is the bundled synthetic sample media.
        var url: URL {
            let counters = ProcessInfo.processInfo.environment["JOVRA_FRAME_COUNTER_DIR"].map { URL(fileURLWithPath: $0) }
            let located: URL? = switch self {
            case .fc060: counters?.appendingPathComponent("frame-counter-060fps.mp4")
            case .fc240: counters?.appendingPathComponent("frame-counter-240fps.mp4")
            case .sample: Bundle.main.url(forResource: "sample-jon-vs-alex", withExtension: "mp4", subdirectory: "SampleMedia")
            case .missing: nil
            }
            return located ?? FileManager.default.temporaryDirectory.appendingPathComponent("not-on-this-iphone-\(rawValue).mp4")
        }
    }

    @State var source: Source
    @State private var playback = VideoLabPlayback()
    private var controller: PlaybackController? {
        playback.requestedSource == source.url ? playback.controller : nil
    }

    private var openError: PlaybackOpenError? {
        playback.requestedSource == source.url ? playback.error : nil
    }
    @State private var zoom = VideoZoom()
    @State private var surfaceSize = CGSize(width: 320, height: 180)
    @State private var pendingLoopStart: Int?
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { proxy in
            Group {
                if verticalSizeClass == .compact {
                    landscape
                } else {
                    portrait
                }
            }
            .padding(.top, proxy.safeAreaInsets.top)
            .ignoresSafeArea(.container, edges: .vertical)
        }
        .background(Color.jovra(.background).ignoresSafeArea())
        .task(id: source) { [requested = source] in await open(requested) }
        .onDisappear { playback.close() }
    }

    // MARK: Layouts

    private var portrait: some View {
        ScrollView {
            ReadableColumn {
                VStack(alignment: .leading, spacing: Space.x2) {
                    header
                    surface
                    controls
                }
                .padding(.horizontal, Space.screenMargin)
                .padding(.bottom, Space.x4)
            }
        }
        .accessibilityIdentifier("videoLab.scroll")
    }

    private var landscape: some View {
        HStack(alignment: .top, spacing: Space.x2) {
            surface
                .frame(maxHeight: .infinity, alignment: .center)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x2) {
                    header
                    controls
                }
                .padding(.bottom, Space.x4)
            }
            .frame(width: 300)
            .accessibilityIdentifier("videoLab.scroll")
        }
        .padding(.horizontal, Space.screenMargin)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text("Video lab")
                .jovraDisplayTitle()
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("screen.title")
            Text("Frame-accurate playback on synthetic clips.")
                .font(.jovraSubtitle)
                .foregroundStyle(.jovra(.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
            if source != .missing {
                FilterPills(options: [Source.fc060, .fc240, .sample], selection: $source) { $0.title }
                    .accessibilityIdentifier("videoLab.sources")
            }
        }
    }

    // MARK: Surface

    private var surface: some View {
        VideoSurface(content: surfaceContent, zoom: $zoom) {
            SampleBadge.video
                .accessibilityIdentifier("video.sample")
        } bottomBar: {
            if let controller {
                Text(verbatim: "\(time(controller.currentFrame, controller)) / \(time(controller.frameCount - 1, controller))")
                    .font(.jovraCaption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.jovra(.textOnEditorial))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    // A glanceable duplicate of the readout (hidden from VoiceOver): it stops growing before it
                    // would cover the picture; the readout below follows every text size.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .padding(.horizontal, Space.x1)
                    .frame(maxWidth: .infinity, minHeight: HitTarget.minimum, alignment: .leading)
                    .accessibilityHidden(true)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { surfaceSize = $0 }
    }

    private var surfaceContent: VideoSurfaceContent {
        if let openError {
            if openError == .missingFile {
                return .missing(title: "Video missing", message: "The original isn't on this iPhone.", action: nil)
            }
            return .failed(title: "Couldn't play this video", message: "The file is on this iPhone but can't be played here.")
        }
        guard let controller else { return .loading(poster: nil) }
        return .player(controller.player, still: controller.still?.image)
    }

    // MARK: Controls

    @ViewBuilder private var controls: some View {
        if let controller {
            VStack(alignment: .leading, spacing: 0) {
                PlaybackTimeline(frame: controller.currentFrame, frameCount: controller.frameCount,
                                 currentTimeText: time(controller.currentFrame, controller),
                                 durationText: time(controller.frameCount - 1, controller),
                                 onScrub: { controller.scrub(toFrame: $0) },
                                 onScrubEnded: controller.finishScrub(atFrame:))
                Spacer().frame(height: VideoMetrics.timelineToJogGap)
                jog(controller)
                Spacer().frame(height: Space.x3)
                TransportBar(isPlaying: controller.isPlaying, rate: controller.rate, canPlaySlow: controller.canPlaySlowForward,
                             timeText: time(controller.currentFrame, controller),
                             onRate: { controller.setRate($0) },
                             onStep: { count in Task { await controller.step(byCount: count) } },
                             onPlayPause: { controller.togglePlayPause() }) {
                    loopButton(controller)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("transport")
                Spacer().frame(height: Space.x3)
                secondaryRow(controller)
                Spacer().frame(height: Space.x2)
                status(controller)
            }
        } else if source == .missing || openError != nil {
            Text("Scrubbing and stepping come back when the video is on this iPhone.")
                .font(.jovraBody)
                .foregroundStyle(.jovra(.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func jog(_ controller: PlaybackController) -> some View {
        let readout = FrameReadout(readout: controller.readout)
        let strip = JogStrip(frame: controller.currentFrame, frameCount: controller.frameCount,
                             framesPerSecond: Int(controller.frameRate.framesPerSecond.rounded()),
                             timeText: time(controller.currentFrame, controller),
                             onScrub: { controller.scrub(toFrame: $0) },
                             onScrubEnded: { frame in Task { await controller.endScrub(atFrame: frame) } },
                             onStep: { count in Task { await controller.step(byCount: count) } })
        return VStack(alignment: .trailing, spacing: Space.x1) {
            strip
            readout
        }
    }

    private func loopButton(_ controller: PlaybackController) -> some View {
        let active = controller.loop != nil
        let label = active ? "Clear loop" : (pendingLoopStart == nil ? "Set loop start" : "Set loop end")
        let face = active ? "A–B" : (pendingLoopStart == nil ? "A" : "B")
        return Button {
            if active {
                controller.setLoop(nil)
                pendingLoopStart = nil
            } else if let start = pendingLoopStart {
                controller.setLoop(FrameLoop(start: start, end: controller.currentFrame, frameCount: controller.frameCount))
                pendingLoopStart = nil
            } else {
                pendingLoopStart = controller.currentFrame
            }
        } label: {
            Text(verbatim: face)
                .font(.headline)
                .fixedSize()
                .transportDisc(.secondary, isSelected: active)
        }
        .buttonStyle(TransportPressStyle())
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(loopValue(controller)))
        .accessibilityShowsLargeContentViewer { Label(label, systemImage: "repeat") }
        .accessibilityIdentifier("transport.loop")
    }

    private func loopValue(_ controller: PlaybackController) -> String {
        if let loop = controller.loop { return "f \(JovraFormat.count(loop.start)) to f \(JovraFormat.count(loop.end))" }
        if let pendingLoopStart { return "Starts at f \(JovraFormat.count(pendingLoopStart))" }
        return "Off"
    }

    private func secondaryRow(_ controller: PlaybackController) -> some View {
        let skips = HStack(spacing: Space.x1) {
            skipButton(-10, controller)
            skipButton(10, controller)
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.x2) {
                skips
                Spacer(minLength: 0)
                ZoomControl(zoom: $zoom, surfaceSize: surfaceSize)
            }
            VStack(alignment: .leading, spacing: Space.x2) {
                skips
                ZoomControl(zoom: $zoom, surfaceSize: surfaceSize)
            }
        }
    }

    private func skipButton(_ seconds: Int, _ controller: PlaybackController) -> some View {
        let back = seconds < 0
        return Button { Task { await controller.skip(seconds: seconds) } } label: {
            Label(back ? "Back 10 s" : "Forward 10 s", systemImage: back ? "gobackward.10" : "goforward.10")
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
                .transportDisc(.secondary)
        }
        .buttonStyle(TransportPressStyle())
        .accessibilityLabel(Text(back ? "Back 10 seconds" : "Forward 10 seconds"))
        .accessibilityShowsLargeContentViewer { Label(back ? "Back 10 s" : "Forward 10 s", systemImage: back ? "gobackward.10" : "goforward.10") }
        .accessibilityIdentifier(back ? "transport.back10" : "transport.forward10")
    }

    private func status(_ controller: PlaybackController) -> some View {
        let proxy: String = switch controller.proxyState {
        case .none: "Backward steps decode the original."
        case .building: "Preparing a quick-step copy for backward steps…"
        case .ready: "Backward steps use a quick-step copy. The original is unchanged."
        case .failed: "Backward steps decode the original. The quick-step copy didn't check out."
        }
        return Text(proxy)
            .font(.jovraCaption)
            .foregroundStyle(.jovra(.textSecondary))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("videoLab.proxy")
    }

    // MARK: Helpers

    private func time(_ frame: Int, _ controller: PlaybackController) -> String {
        ReadoutFormat.time(seconds: controller.frameRate.seconds(atFrame: max(0, frame)))
    }

    private func open(_ requested: Source) async {
        guard requested == source, !Task.isCancelled else { return }
        zoom.reset()
        pendingLoopStart = nil
        let proxies = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true)
        await playback.load(requested.url, proxyDirectory: proxies)
    }
}
#endif
