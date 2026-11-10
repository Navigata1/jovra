import AVFoundation
import JovraCore
import JovraMedia
import SwiftUI

/// The capture route's container (T17). It owns the coordinator, derives `CaptureRoutePhase` and shows the
/// phase's view; framing, scoring and court mode are slots other tickets fill without editing this file.
/// Without a setup it opens with a default singles draft. Calibration, live scoring and hardware
/// endurance remain separate acceptance gates; no court check, score or stat is fabricated.
struct CaptureScreen: View {
    nonisolated static let isPlaceholder = false
    var setup: SessionSetupDraft?
    @Environment(AppRouter.self) private var router
    @Environment(\.localCaptureLibrary) private var library
    @Environment(\.permissionsCenter) private var permissions
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.captureConfig) private var config
    @State private var choices: CaptureSetupChoices
    @State private var coordinator: NativeCaptureCoordinator?
    @State private var cameraExplanation = false
    @State private var sheet: CaptureSheet?
    @State private var closeAfterSave = false
    @State private var failed = false
    @State private var toasts = ToastCenter(announcer: PoliteAnnouncer())
    @State private var keepAwake = CaptureKeepAwake()

    init(setup: SessionSetupDraft?) {
        self.setup = setup
        _choices = State(initialValue: setup?.captureChoices ?? .defaultSinglesDraft)
    }

    private var phase: CaptureRoutePhase {
        CaptureRoutePhase(enginePhase: coordinator?.status?.phase, isSaved: coordinator?.savedRecording != nil)
    }

    private var isSupported: Bool { setup?.kind == nil || setup?.kind == .singlesMatch }

    /// Set once the engine has stopped with nothing saved: the recording phase then shows what failed.
    private var stopFailure: CaptureStopFailure? {
        guard let coordinator, let status = coordinator.status, coordinator.savedRecording == nil else { return nil }
        return CaptureRecordingState(status).stopFailure(isWorking: coordinator.isSettling, recorded: coordinator.stopFailure)
    }

    var body: some View {
        Group {
            if phase == .recording, isSupported, let coordinator, let status = coordinator.status {
                recordingPhase(coordinator, status: status)
            } else {
                column
            }
        }
        .background(Color.jovra(.background).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) { if sheet == nil { toast } }
        .interactiveDismissDisabled(phase == .recording)
        .task { if choices.isValid { await prepare() } }
        .sheet(isPresented: $cameraExplanation) {
            PermissionExplanationSheet(permission: .camera) { decision in
                if decision == .authorized { Task { await prepare() } }
            }
        }
        .sheet(item: $sheet, onDismiss: sheetDismissed) { presented in sheetContent(presented) }
        .onChange(of: coordinator?.status?.phase) { _, phase in keepAwake.update(for: scenePhase == .active ? phase : nil) }
        .onChange(of: coordinator?.status?.interruption) { _, interruption in
            guard let interruption else { if sheet == .interruption { sheet = nil }; return }
            interrupted(interruption)
        }
        .onChange(of: coordinator?.savedRecording) { _, saved in
            guard let saved else { return }
            PoliteAnnouncer().announce(CaptureRecordingCopy.automaticStopReason(saved) ?? CaptureRecordingCopy.savedAnnouncement)
        }
        .onChange(of: stopFailure) { _, failure in
            if let failure { toasts.dismiss(); PoliteAnnouncer().announce(CaptureRecordingCopy.stopFailureAnnouncement(failure)) }
        }
        // Battery, storage and heat are read again for as long as the recording phase is up; the task
        // ends with the phase. The engine's own stop at low storage or battery lands like the player's.
        .task(id: phase) {
            if phase == .recording { await coordinator?.keepBudgetCurrent() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active { keepAwake.release() } else { keepAwake.update(for: coordinator?.status?.phase) }
            if newPhase == .background, coordinator?.status?.phase == .recording, coordinator?.isWorking == false {
                perform { try await coordinator?.interrupt(reason: .backgrounded) }
            }
        }
        .onDisappear {
            keepAwake.release()
            Task { try? await coordinator?.leaveScreen() }
        }
    }

    // MARK: Phases

    private var column: some View {
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
                    Text((setup?.kind ?? .singlesMatch).title).font(.jovraHeadline).foregroundStyle(.jovra(.textPrimary))
                        .accessibilityIdentifier("capture.kind")
                    columnContent
                }.padding(.horizontal, Space.screenMargin).padding(.bottom, Space.x3)
                    .frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
            }.clipped().scrollDismissesKeyboard(.interactively)
        }
    }

    @ViewBuilder private var columnContent: some View {
        if !isSupported {
            StateCard(symbol: "video.slash", title: String(localized: "This recording mode is not available yet", table: "Capture"),
                      message: String(localized: "Close this screen to keep your selected mode. It will not be replaced with a singles match.", table: "Capture"))
        } else if case .unavailable = library {
            StateCard(symbol: "externaldrive.badge.exclamationmark", title: String(localized: "Local library unavailable", table: "Capture"),
                      message: String(localized: "Close JOVRA and try again. Your existing videos are not removed.", table: "Capture"))
        } else if let coordinator, let saved = coordinator.savedRecording {
            CaptureSavedPhase(recording: saved, isFixture: coordinator.isFixture,
                              openLibrary: { router.show(.tab(.sessions)) }, done: { router.dismissFullScreen() })
        } else if let coordinator {
            CaptureFramingPhase(coordinator: coordinator, choices: choices, fixture: fixtureURL,
                                editDetails: { sheet = .editDetails },
                                start: { perform { try await coordinator.start() } })
        } else {
            CaptureSetupFields(choices: $choices)
            Button(String(localized: "Frame your court", table: "Capture")) { Task { await prepare() } }
                .buttonStyle(.jovraPrimary).disabled(!choices.isValid).accessibilityIdentifier("capture.prepare")
            if coordinator == nil, choices.isValid, !failed {
                ProgressView(String(localized: "Preparing your recording", table: "Capture"))
                    .tint(.jovra(.textPrimary)).foregroundStyle(.jovra(.textPrimary))
            }
        }
        if failed, coordinator?.savedRecording == nil {
            StateCard(symbol: "exclamationmark.triangle", title: String(localized: "Recording unavailable", table: "Capture"),
                      message: String(localized: "Your existing footage stays on this iPhone. Close this screen and try again.", table: "Capture"))
        }
    }

    private func recordingPhase(_ coordinator: NativeCaptureCoordinator, status: CaptureStatus) -> some View {
        var simulate: (() -> Void)?
        #if DEBUG
        if coordinator.isFixture { simulate = { perform { try await coordinator.interrupt(reason: .interruption) } } }
        #endif
        return CaptureRecordingPhase(
            state: CaptureRecordingState(status), previewSession: coordinator.previewSession,
            fixture: coordinator.isFixture ? fixtureURL : nil, isFixture: coordinator.isFixture,
            batteryFraction: coordinator.batteryFraction, previewMode: status.previewMode,
            isWorking: coordinator.isWorking, failed: failed, stopFailure: stopFailure,
            competitionMode: config.competitionMode, isObscured: sheet != nil,
            actions: .init(markPoint: { markPoint(coordinator) },
                           pause: { perform { try await coordinator.pause() } },
                           resume: { perform { try await coordinator.resume() } },
                           stop: { sheet = .stopConfirmation },
                           delete: { sheet = .deleteConfirmation },
                           retryDelete: { delete() },
                           close: { router.dismissFullScreen() },
                           simulateInterruption: simulate))
    }

    // MARK: Sheets

    @ViewBuilder private func sheetContent(_ presented: CaptureSheet) -> some View {
        switch presented {
        case .stopConfirmation:
            CaptureDecisionSheet(
                symbol: "stop.circle", title: String(localized: "Stop recording?", table: "Capture"),
                message: String(localized: "Your video is saved on this iPhone.", table: "Capture"),
                primary: .init(title: String(localized: "Stop and save", table: "Capture"), identifier: "capture.confirmStop") {
                    sheet = nil; stop()
                },
                secondary: .init(title: String(localized: "Keep recording", table: "Capture"), identifier: "capture.keepRecording") {
                    closeAfterSave = false; sheet = nil
                },
                identifier: "capture.stopSheet")
        case .deleteConfirmation:
            CaptureDecisionSheet(
                symbol: "trash", title: String(localized: "Delete this recording?", table: "Capture"),
                message: String(localized: "Everything recorded in this session is removed from this iPhone. This cannot be undone.", table: "Capture"),
                primary: .init(title: String(localized: "Delete recording", table: "Capture"), identifier: "capture.confirmDelete",
                               isDestructive: true) { sheet = nil; delete() },
                secondary: .init(title: String(localized: "Keep recording", table: "Capture"), identifier: "capture.keepRecording") { sheet = nil },
                identifier: "capture.deleteSheet")
        case .interruption:
            if let interruption = coordinator?.status?.interruption {
                CaptureDecisionSheet(
                    symbol: "pause.circle", title: CaptureRecordingCopy.interruptionTitle(interruption),
                    message: CaptureRecordingCopy.interruptionMessage(interruption),
                    primary: .init(title: String(localized: "Resume recording", table: "Capture"), identifier: "capture.interruption.resume") {
                        sheet = nil; perform { try await coordinator?.resume() }
                    },
                    secondary: .init(title: String(localized: "Finish session", table: "Capture"), identifier: "capture.interruption.finish") {
                        sheet = nil; stop()
                    },
                    identifier: "capture.interruptionSheet") {
                    StatusPill(text: CaptureRecordingCopy.segmentSaved(savedThroughMs ?? interruption.startMs), tone: .positive)
                        .accessibilityIdentifier("capture.segmentSaved")
                    CaptureGapList(gaps: coordinator?.status?.gaps ?? [], ink: .textSecondary)
                }
            }
        case .editDetails:
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x2) {
                    Text("Edit match details", tableName: "Capture")
                        .font(.title2.weight(.bold)).foregroundStyle(.jovra(.textPrimary))
                        .accessibilityAddTraits(.isHeader)
                    CaptureSetupFields(choices: $choices)
                    Button(String(localized: "Done", table: "Capture")) { sheet = nil }
                        .buttonStyle(.jovraPrimary).disabled(!choices.isValid)
                        .accessibilityIdentifier("capture.details.done")
                }
                .padding(Space.screenMargin)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.jovra(.background).ignoresSafeArea())
            .presentationDetents([.large])
            .interactiveDismissDisabled()
        }
    }

    private func sheetDismissed() {
        if choices.isValid { try? coordinator?.updateSeed(choices.seed) }
    }

    // MARK: Actions

    @ViewBuilder private var toast: some View {
        if let message = toasts.current {
            ToastView(message: message, undo: toasts.undo, dismiss: toasts.dismiss)
                .padding(.horizontal, Space.screenMargin)
                .padding(.top, 64)
                .frame(maxWidth: ReadableColumn.maximumWidth)
                .transition(.opacity)
                .id(message.id)
        }
    }

    private var fixtureURL: URL? { Bundle.main.url(forResource: "fixture-camera-720p30", withExtension: "mp4") }

    private func prepare() async {
        guard choices.isValid, coordinator == nil, isSupported, case .ready(let library) = library else { return }
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

    private func markPoint(_ coordinator: NativeCaptureCoordinator) {
        do {
            let at = try EngineMarkPointAction(coordinator: coordinator).markPoint()
            toasts.show(String(localized: "Point marked · \(CaptureRecordingCopy.clock(at))", table: "Capture"))
        } catch { failed = true }
    }

    /// The segment closed: VoiceOver hears it politely and the sheet confirms "Segment saved" before asking
    /// to resume. A toast would sit unreadable behind the sheet, so the confirmation lives in it.
    private func interrupted(_ interruption: CaptureInterruption) {
        toasts.dismiss()
        PoliteAnnouncer().announce(CaptureRecordingCopy.interruptedAnnouncement(interruption))
        if sheet == nil { sheet = .interruption }
    }

    private var savedThroughMs: Int? {
        coordinator?.status?.savedThrough.map { Int($0.value * 1000 / Int64(max(1, $0.timescale))) }
    }

    private func stop() {
        perform {
            try await coordinator?.stop()
            if closeAfterSave { router.dismissFullScreen() }
        }
    }

    private func delete() {
        guard let coordinator, let id = coordinator.sessionID else { return }
        perform {
            try await coordinator.deleteRecording()
            PoliteAnnouncer().announce(CaptureRecordingCopy.deletedAnnouncement)
            config.onConsentWithdrawn?(id)
            router.dismissFullScreen()
        }
    }

    private func perform(_ action: @escaping () async throws -> Void) {
        Task { do { try await action() } catch { failed = true } }
    }

    private func close() {
        if coordinator?.status?.phase == .recording || coordinator?.status?.phase == .paused {
            closeAfterSave = true; sheet = .stopConfirmation
        } else { router.dismissFullScreen() }
    }
}
