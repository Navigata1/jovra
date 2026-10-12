import AVFoundation
import JovraCore
import JovraMedia
import SwiftUI

/// Bounded singles framing and recording. Calibration, live scoring and hardware endurance
/// remain separate acceptance gates; no court checks or stats are fabricated.
struct CaptureScreen: View {
    nonisolated static let isPlaceholder = false
    var setup: SessionSetupDraft?
    @Environment(AppRouter.self) private var router
    @Environment(\.localCaptureLibrary) private var library
    @Environment(\.permissionsCenter) private var permissions
    @Environment(\.scenePhase) private var scenePhase
    @State private var choices: CaptureSetupChoices
    @State private var coordinator: NativeCaptureCoordinator?
    @State private var cameraExplanation = false
    @State private var confirmStop = false
    @State private var closeAfterSave = false
    @State private var failed = false
    @State private var marked = false

    init(setup: SessionSetupDraft?) {
        self.setup = setup
        _choices = State(initialValue: setup?.captureChoices ?? .init())
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CloseControl(label: String(localized: "Close capture", table: "Capture"), identifier: "capture.close") { close() }
                Spacer()
                JovraLockup(height: 28)
            }.padding(Space.x2)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x2) {
                    Text(AppDestination.fullScreen(.capture(setup)).info.title)
                        .jovraDisplayTitle().accessibilityAddTraits(.isHeader).accessibilityIdentifier("screen.title")
                    Text((setup?.kind ?? .singlesMatch).title).font(.jovraHeadline).accessibilityIdentifier("capture.kind")
                    content
                }.padding(.horizontal, Space.screenMargin).padding(.bottom, Space.x3)
                    .frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
            }.clipped().scrollDismissesKeyboard(.interactively)
        }
        .background(Color.jovra(.background).ignoresSafeArea()).preferredColorScheme(.dark)
        .task { if choices.isValid { await prepare() } }
        .sheet(isPresented: $cameraExplanation) {
            PermissionExplanationSheet(permission: .camera) { decision in
                if decision == .authorized { Task { await prepare() } }
            }
        }
        .confirmationDialog(String(localized: "Stop recording?", table: "Capture"), isPresented: $confirmStop) {
            Button(String(localized: "Stop and save", table: "Capture")) {
                perform { try await coordinator?.stop(); if closeAfterSave { router.dismissFullScreen() } }
            }.accessibilityIdentifier("capture.confirmStop")
            Button(String(localized: "Keep recording", table: "Capture"), role: .cancel) { closeAfterSave = false }
        } message: { Text("Your video stays on this iPhone.", tableName: "Capture") }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, coordinator?.status?.phase == .recording, coordinator?.isWorking == false {
                perform { try await coordinator?.pause() }
            }
        }
        .onDisappear { Task { try? await coordinator?.leaveScreen() } }
    }

    @ViewBuilder private var content: some View {
        if let kind = setup?.kind, kind != .singlesMatch {
            StateCard(symbol: "video.slash", title: String(localized: "This recording mode is not available yet", table: "Capture"),
                      message: String(localized: "Close this screen to keep your selected mode. It will not be replaced with a singles match.", table: "Capture"))
        } else if case .unavailable = library {
            StateCard(symbol: "externaldrive.badge.exclamationmark", title: String(localized: "Local library unavailable", table: "Capture"),
                      message: String(localized: "Close JOVRA and try again. Your existing videos are not removed.", table: "Capture"))
        } else if let coordinator {
            recording(coordinator)
        } else {
            CaptureSetupFields(choices: $choices)
            Button(String(localized: "Frame your court", table: "Capture")) { Task { await prepare() } }
                .buttonStyle(.jovraPrimary).disabled(!choices.isValid).accessibilityIdentifier("capture.prepare")
        }
        if failed {
            StateCard(symbol: "exclamationmark.triangle", title: String(localized: "Recording unavailable", table: "Capture"),
                      message: String(localized: "Your existing footage stays on this iPhone. Close this screen and try again.", table: "Capture"))
        }
    }

    @ViewBuilder private func recording(_ coordinator: NativeCaptureCoordinator) -> some View {
        if coordinator.isFixture {
            FixtureBadge()
            SampleBadge(onForest: true).accessibilityIdentifier("capture.sample")
        }
        if coordinator.savedRecording != nil {
            Label(String(localized: "Saved on this iPhone", table: "Capture"), systemImage: "checkmark.circle")
                .font(.jovraHeadline).accessibilityIdentifier("capture.saved")
            Button(String(localized: "Open library", table: "Sessions.Library")) { router.show(.tab(.sessions)) }
                .buttonStyle(.jovraPrimary).accessibilityIdentifier("capture.openLibrary")
        } else {
            CapturePreview(session: coordinator.previewSession, fixture: coordinator.isFixture ? fixtureURL : nil)
                .aspectRatio(16 / 9, contentMode: .fit).frame(minHeight: 180).accessibilityHidden(true)
            if coordinator.isFixture { Text("Sample footage preview", tableName: "Capture").font(.jovraLabel) }
            if let status = coordinator.status {
                if status.phase == .ready {
                    Text("Frame your court", tableName: "Capture").font(.jovraHeadline)
                    Text("Position behind the baseline and align the court in the frame. Calibration can be added after recording.", tableName: "Capture")
                        .fixedSize(horizontal: false, vertical: true)
                    control(String(localized: "Start recording", table: "Capture"), id: "capture.start") { try await coordinator.start() }
                } else {
                    Text(CapturePhasePresentation.title(for: status.phase))
                        .font(.jovraHeadline).accessibilityIdentifier("capture.phase")
                    if let time = status.recordingTime { Text("Session time: \(clockText(time))", tableName: "Capture").monospacedDigit() }
                    if let time = status.savedThrough, time.value > 0 {
                        Text("Saved through \(clockText(time))", tableName: "Capture").accessibilityIdentifier("capture.confirmedTime")
                    }
                    if status.phase == .recording {
                        control(String(localized: "Mark point", table: "Capture"), id: "capture.markPoint") { try coordinator.markPoint(); marked = true }
                        control(String(localized: "Pause", table: "Capture"), id: "capture.pause") { try await coordinator.pause() }
                    } else if status.phase == .paused {
                        control(String(localized: "Resume", table: "Capture"), id: "capture.resume") { try await coordinator.resume() }
                    }
                    if status.phase == .recording || status.phase == .paused {
                        control(String(localized: "Stop recording", table: "Capture"), id: "capture.stop") { confirmStop = true }
                    }
                    if marked { Text("Point marked", tableName: "Capture").accessibilityIdentifier("capture.marked") }
                }
            }
            Text("No sound · Video records without microphone access", tableName: "Capture").font(.jovraLabel)
            if coordinator.isWorking { ProgressView().accessibilityLabel(String(localized: "Preparing your recording", table: "Capture")) }
        }
    }

    private func control(_ title: String, id: String, action: @escaping () async throws -> Void) -> some View {
        Button { perform(action) } label: { Text(title).frame(maxWidth: .infinity, minHeight: 64) }
            .buttonStyle(.jovraPrimary).disabled(coordinator?.isWorking != false).accessibilityIdentifier(id)
    }

    private var fixtureURL: URL? { Bundle.main.url(forResource: "fixture-camera-720p30", withExtension: "mp4") }

    private func prepare() async {
        guard choices.isValid, coordinator == nil, setup?.kind == nil || setup?.kind == .singlesMatch,
              case .ready(let library) = library else { return }
        #if targetEnvironment(simulator)
        guard let fixtureURL else { failed = true; return }
        let clock = RealtimeCaptureClock()
        let source: any CaptureSource = FixtureCamera(url: fixtureURL, clock: clock)
        #else
        guard await permissions.status(of: .camera) == .authorized else { cameraExplanation = true; return }
        let clock = RealtimeCaptureClock()
        let source: any CaptureSource = CameraSource()
        #endif
        let candidate = NativeCaptureCoordinator(library: library, source: source, clock: clock)
        coordinator = candidate
        do { try await candidate.prepare(seed: choices.seed, preset: .init(width: 1280, height: 720, bitRate: 4_000_000), microphone: .notRequested) }
        catch { failed = true }
    }

    private func perform(_ action: @escaping () async throws -> Void) {
        Task { do { try await action() } catch { failed = true } }
    }

    private func close() {
        if coordinator?.status?.phase == .recording || coordinator?.status?.phase == .paused {
            closeAfterSave = true; confirmStop = true
        } else { router.dismissFullScreen() }
    }

    private func clockText(_ time: JovraCore.MediaTime) -> String {
        let seconds = max(0, Int(time.value / Int64(time.timescale)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
