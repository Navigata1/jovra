import AVFoundation
import JovraCore
import JovraMedia
import SwiftUI

/// S06, the recording phase: the full-bleed preview with the REC and battery pills, the score overlay and
/// court-mode slots, and an opaque forest control panel (portrait) or a trailing control rail (landscape).
/// The phase shows only what the engine confirmed. There is no live ball speed, body tracking or call on
/// whether a ball was in; the phone's job here is to keep the video safe. When the engine has stopped
/// without a saved recording (`stopFailure`), the controls give way to what failed and the ways out.
struct CaptureRecordingPhase: View {
    struct Actions {
        var markPoint: () -> Void
        var pause: () -> Void
        var resume: () -> Void
        var stop: () -> Void
        var delete: () -> Void
        /// A deletion that failed, tried again without a second confirmation.
        var retryDelete: () -> Void
        /// Leaves the route once the engine has stopped without a saved recording.
        var close: () -> Void
        var simulateInterruption: (() -> Void)?
    }

    var state: CaptureRecordingState
    var previewSession: AVCaptureSession?
    var fixture: URL?
    var isFixture: Bool
    var batteryFraction: Double?
    var previewMode: CapturePreviewMode
    var isWorking: Bool
    var failed: Bool
    /// The engine stopped and nothing was acknowledged as saved: say so, and offer the ways out.
    var stopFailure: CaptureStopFailure?
    var competitionMode: Bool
    /// A question sheet is up: the chrome over the video steps back so the sheet is the only thing to read.
    var isObscured = false
    var actions: Actions

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var statusHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            if verticalSizeClass == .compact {
                landscape(geometry)
            } else {
                portrait(geometry)
            }
        }
        .background(Color.jovra(.background).ignoresSafeArea())
    }

    // MARK: Layouts

    private func portrait(_ geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                preview
                ScrollView {
                    overlays.padding(.horizontal, Space.x2).padding(.top, Space.x1)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxHeight: .infinity)
            // Stopped, the words matter more than the preview: they get half the screen before scrolling.
            panel(statusLimit: geometry.size.height * (stopFailure == nil ? 0.34 : 0.5))
        }
    }

    private func landscape(_ geometry: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                preview
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.x2) {
                        overlays
                        if stopFailure == nil {
                            Spacer(minLength: Space.x2)
                            statusBlock.padding(Space.x2)
                                .frame(maxWidth: 460, alignment: .leading)
                                .background(Color.jovra(.background), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                        }
                    }
                    .padding(Space.x2)
                    .frame(minHeight: geometry.size.height, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            if let stopFailure {
                stoppedColumn(stopFailure)
                    .frame(width: min(max(geometry.size.width * 0.44, 300), 440))
                    .background(Color.jovra(.background).ignoresSafeArea())
            } else {
                ScrollView {
                    VStack(spacing: Space.x3) {
                        controls(axis: .vertical)
                        moreMenu
                    }
                    .padding(.vertical, Space.x2)
                    .frame(minHeight: geometry.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(width: 112)
                .background(Color.jovra(.background).ignoresSafeArea())
            }
        }
    }

    /// Landscape, stopped: the rail's place is taken by what failed, with the ways out pinned under it so
    /// they stay on screen however long the words run at large text sizes.
    private func stoppedColumn(_ failure: CaptureStopFailure) -> some View {
        VStack(spacing: Space.x2) {
            ScrollView { statusBlock }
                .scrollBounceBehavior(.basedOnSize)
            exits(failure)
        }
        .padding(Space.x2)
    }

    private func exits(_ failure: CaptureStopFailure) -> some View {
        // Never squeezed by the preview or the scrolling words above: at the largest text sizes a
        // compressed button would let its label spill out of its capsule.
        CaptureStoppedExits(failure: failure, isWorking: isWorking, retryDelete: actions.retryDelete, close: actions.close)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Pieces

    private var preview: some View {
        ZStack {
            Color.black
            // Court mode says the preview is off, so the preview is removed, not only covered.
            if previewMode != .courtMode {
                CapturePreview(session: previewSession, fixture: fixture)
                    .accessibilityHidden(true)
            }
            CaptureCourtModeSlot(previewMode: previewMode)
        }
        .ignoresSafeArea(edges: verticalSizeClass == .compact ? [.leading, .vertical] : .top)
    }

    /// Top row and the slots that sit over the preview.
    private var overlays: some View {
        VStack(alignment: .leading, spacing: Space.x1 + Space.half) {
            HStack(alignment: .top, spacing: Space.x1) {
                RecordingStatusPill(state: state)
                Spacer(minLength: Space.x1)
                if verticalSizeClass != .compact, !dynamicTypeSize.isAccessibilitySize {
                    JovraLockup(height: 28).padding(.top, Space.x1)
                    Spacer(minLength: Space.x1)
                }
                if let batteryFraction { BatteryPill(fraction: batteryFraction) }
            }
            CaptureScoreOverlaySlot(competitionMode: competitionMode)
            if isFixture {
                FixtureBadge()
                SampleBadge(onForest: true).accessibilityIdentifier("capture.sample")
                if let simulate = actions.simulateInterruption, state.isRecording {
                    Button(String(localized: "Simulate interruption", table: "Capture"), action: simulate)
                        .buttonStyle(.jovraCompact)
                        .background(Color.jovra(.background), in: Capsule())
                        .disabled(isWorking)
                        .accessibilityIdentifier("capture.debug.interrupt")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isObscured ? 0 : 1)
        .accessibilityHidden(isObscured)
    }

    @ViewBuilder private var statusBlock: some View {
        if let stopFailure {
            CaptureStoppedStatus(failure: stopFailure, savedThroughMs: state.savedThroughMs)
        } else {
            liveStatus
        }
    }

    private var liveStatus: some View {
        VStack(alignment: .leading, spacing: Space.x1 + Space.half) {
            if state.isPlayerPause { CaptureNotRecordingBanner.paused }
            CaptureSaveStatus(state: state)
            CaptureGapList(gaps: state.gaps)
            // Stopped with the save still in flight is the same moment to the player as stopping.
            if state.pill == .stopped {
                Label {
                    Text("Stopping and saving", tableName: "Capture")
                } icon: {
                    ProgressView().tint(.jovra(.textOnEditorial))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.jovra(.textOnEditorial))
            }
            if failed {
                Label {
                    Text("Recording unavailable. Your existing footage stays on this iPhone.", tableName: "Capture")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.jovra(.attentionInk))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("capture.failed")
            }
        }
    }

    private func panel(statusLimit: CGFloat) -> some View {
        VStack(spacing: Space.x2) {
            HStack(alignment: .top, spacing: Space.x1) {
                // As tall as the status needs, up to `statusLimit`; beyond that (large text, many gaps) it scrolls.
                ScrollView {
                    statusBlock.background(GeometryReader { proxy in
                        Color.clear.preference(key: StatusHeightKey.self, value: proxy.size.height)
                    })
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(max(statusHeight, HitTarget.minimum), statusLimit))
                .onPreferenceChange(StatusHeightKey.self) { statusHeight = $0 }
                if stopFailure == nil, !overflowJoinsControls { moreMenu }
            }
            if let stopFailure { exits(stopFailure) } else { controls(axis: .horizontal) }
        }
        .padding(.horizontal, Space.screenMargin)
        .padding(.top, Space.x3)
        .padding(.bottom, Space.x2)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: Radius.sheet, topTrailingRadius: Radius.sheet, style: .continuous)
                .fill(Color.jovra(.background))
                .ignoresSafeArea(edges: .bottom)
        )
    }

    /// At accessibility text sizes the overflow joins the control row, as it does in the landscape rail,
    /// so the save status and its gaps get the panel's full width.
    private var overflowJoinsControls: Bool { dynamicTypeSize.isAccessibilitySize }

    /// In the row every disc is centred on Stop's centre line (reference 06), with captions hanging below.
    private func rowInset(_ diameter: CGFloat, axis: Axis) -> CGFloat {
        axis == .horizontal ? (CaptureControlButton.stopDiameter - diameter) / 2 : 0
    }

    @ViewBuilder private func controls(axis: Axis) -> some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(alignment: .top, spacing: Space.x1))
            : AnyLayout(VStackLayout(alignment: .center, spacing: Space.x3))
        let ringInset = rowInset(HitTarget.capture, axis: axis)
        layout {
            CaptureControlButton(title: String(localized: "Mark point", table: "Capture"), symbol: "bookmark.fill",
                                 identifier: "capture.markPoint", action: actions.markPoint)
                .disabled(!state.isRecording || isWorking)
                .padding(.top, ringInset)
                .frame(maxWidth: .infinity)
            CaptureControlButton(kind: .stop, title: String(localized: "Stop recording", table: "Capture"), symbol: "stop.fill",
                                 identifier: "capture.stop", action: actions.stop)
                .disabled(isWorking || !(state.isRecording || state.phase == .paused))
                .frame(maxWidth: .infinity)
            if state.phase == .paused {
                CaptureControlButton(title: String(localized: "Resume", table: "Capture"), symbol: "record.circle",
                                     identifier: "capture.resume", action: actions.resume)
                    .disabled(isWorking)
                    .padding(.top, ringInset)
                    .frame(maxWidth: .infinity)
            } else {
                CaptureControlButton(title: String(localized: "Pause", table: "Capture"), symbol: "pause.fill",
                                     identifier: "capture.pause", action: actions.pause)
                    .disabled(!state.isRecording || isWorking)
                    .padding(.top, ringInset)
                    .frame(maxWidth: .infinity)
            }
            if axis == .horizontal, overflowJoinsControls {
                moreMenu.padding(.top, rowInset(HitTarget.minimum, axis: axis))
            }
        }
    }

    /// The overflow (S06): "Delete this recording" for withdrawn consent (user story 89).
    private var moreMenu: some View {
        Menu {
            Button(role: .destructive, action: actions.delete) {
                Label(String(localized: "Delete this recording", table: "Capture"), systemImage: "trash")
            }
            .accessibilityIdentifier("capture.delete")
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.bold))
                .foregroundStyle(.jovra(.textOnEditorial))
                .frame(width: HitTarget.minimum, height: HitTarget.minimum)
                .background(Color.jovra(.surfaceSunken), in: Circle())
        }
        .disabled(isWorking || !(state.isRecording || state.phase == .paused))
        .accessibilityLabel(Text("More recording options", tableName: "Capture"))
        .accessibilityIdentifier("capture.more")
    }
}

private struct StatusHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
