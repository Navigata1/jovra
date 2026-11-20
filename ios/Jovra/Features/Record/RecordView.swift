import JovraCore
import JovraMedia
import SwiftUI

/// Session setup (S04, the Record tab root): choose a mode, make the few decisions that change recording
/// or scoring, see a computed storage, battery and heat budget, then check the camera position.
struct RecordView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.sessionSetupStore) private var store
    @Environment(\.deviceBudget) private var deviceBudget
    @Environment(\.localCaptureLibrary) private var library
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let setup = store.setup
        JovraScreen(title: SetupCopy.title, subtitle: SetupCopy.subtitle) {
            modes(selected: setup.mode)
            SetupRowGroup {
                playersRow(setup)
                if setup.mode.isMatch { scoringRow(setup) }
                GearRowSlot()
                cameraRow
                microphoneRow
                ConsentRowSlot()
                if !setup.mode.isMatch { cameraAngleRow(setup) }
            }
            PreflightStrip(checks: store.preflight)
            if storageIsShort, let format = store.selectedFormat {
                BannerView(tone: .attention,
                           title: String(localized: "Not enough space for the planned length", table: "Record", comment: "Low space banner"),
                           message: String(localized: "Recording still starts and warns you before space runs out. A smaller preset or a shorter plan fits more.", table: "Record", comment: "Low space banner"),
                           primaryAction: .init(title: String(localized: "Change camera preset", table: "Record", comment: "Low space banner action")) {
                               router.present(sheet: .cameraPreset)
                           })
                    .accessibilityIdentifier("record.lowSpace.\(format.id)")
            }
            if !setup.problems.isEmpty { problems(setup) }
            actions(ready: setup.isReady)
        }
        .jovraHaptic(.selection, trigger: setup.mode)
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refresh() } } }
    }

    private func refresh() async {
        await store.refreshDevice(budget: deviceBudget) { await CameraFormatSource.load() }
        await store.refreshRecentPlayers(from: library)
    }

    private var storageIsShort: Bool {
        guard let verdict = store.storageEstimate?.verdict else { return false }
        return verdict != .ready
    }

    // MARK: Modes

    private func modes(selected: SessionSetup.Mode) -> some View {
        VStack(alignment: .leading, spacing: Space.x1 + Space.half) {
            let all = SessionSetup.Mode.allCases
            ForEach(Array(all.enumerated()), id: \.element) { index, mode in
                ModeRow(mode: mode, isSelected: mode == selected, position: index + 1, count: all.count) {
                    store.select(mode)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Session mode", tableName: "Record", comment: "VoiceOver name of the mode radio group"))
    }

    // MARK: Rows

    private func playersRow(_ setup: SessionSetup) -> some View {
        let missing = setup.seatsInPlay.contains { setup[$0].trimmedName.isEmpty }
        let detail = missing
            ? String(localized: "Add names to keep score", table: "Record", comment: "Players row detail when a name is missing")
            : SetupCopy.handednessDetail(setup)
        return SetupRow(symbol: "person.2", label: SetupCopy.playersLabel, value: SetupCopy.playersValue(setup),
                        detail: detail, detailIsAttention: missing && setup.mode.isMatch, identifier: "record.players",
                        action: { router.present(sheet: .players) })
    }

    private func scoringRow(_ setup: SessionSetup) -> some View {
        SetupRow(symbol: "trophy", label: SetupCopy.scoringLabel, value: FormatLabel.summary(setup.format.summary),
                 identifier: "record.scoring", action: { router.present(sheet: .matchFormat(.sessionSetup)) })
    }

    @ViewBuilder private var cameraRow: some View {
        let open = { router.present(sheet: .cameraPreset) }
        if let format = store.selectedFormat {
            let estimate = store.storageEstimate
            SetupRow(symbol: "video", label: SetupCopy.cameraLabel, value: SetupCopy.cameraValue(format),
                     detail: estimate.map(SetupCopy.storageDetail), detailIsAttention: storageIsShort,
                     spokenNote: format.lens == .fixture ? String(localized: "Simulator fixture camera", table: "Record", comment: "Camera row on the simulator, spoken with the badge") : nil,
                     identifier: "record.camera", action: open) {
                if format.lens == .fixture { FixtureBadge().padding(.vertical, Space.half) }
            }
        } else {
            SetupRow(symbol: "video", label: SetupCopy.cameraLabel,
                     value: store.cameraFormats == nil ? SetupCopy.checkingCamera : SetupCopy.noSupportedFormat,
                     detail: store.cameraFormats == nil ? nil
                        : String(localized: "You can still import a recording.", table: "Record", comment: "Camera row when nothing can be recorded"),
                     identifier: "record.camera", action: open)
        }
    }

    private var microphoneRow: some View {
        @Bindable var store = store
        return Toggle(isOn: $store.setup.microphoneOn) {
            HStack(alignment: .center, spacing: Space.x2) {
                MicrophoneSymbol(isOn: store.setup.microphoneOn)
                VStack(alignment: .leading, spacing: 2) {
                    Text(SetupCopy.microphoneLabel)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.jovra(.textSecondary))
                    Text(SetupCopy.microphoneDetail(on: store.setup.microphoneOn))
                        .font(.body)
                        .foregroundStyle(.jovra(.textPrimary))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("record.microphone.detail")
                }
            }
        }
        .tint(.jovra(.positiveInk))
        .padding(.vertical, Space.x1 + Space.half)
        .frame(minHeight: 64)
        .accessibilityIdentifier("record.microphone")
    }

    private func cameraAngleRow(_ setup: SessionSetup) -> some View {
        @Bindable var store = store
        return Menu {
            Picker(SetupCopy.cameraAngleLabel, selection: $store.setup.purpose) {
                ForEach(SessionDocumentCapturePurpose.allCases, id: \.self) { purpose in
                    Text(SetupCopy.purpose(purpose)).tag(purpose)
                }
            }
        } label: {
            SetupRow(symbol: "camera.metering.center.weighted", label: SetupCopy.cameraAngleLabel,
                     value: SetupCopy.purpose(setup.purpose), detail: SetupCopy.purposeDetail(setup.purpose),
                     identifier: "record.cameraAngle.row")
        }
        .buttonStyle(SetupRowButtonStyle())
        .accessibilityIdentifier("record.cameraAngle")
    }

    // MARK: Problems and actions

    private func problems(_ setup: SessionSetup) -> some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Label {
                Text("Before you record", tableName: "Record", comment: "Heading over what still needs fixing")
                    .font(.body.weight(.semibold))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.jovra(.attentionInk))
            }
            ForEach(Array(setup.problems.enumerated()), id: \.offset) { _, problem in
                Text(SetupCopy.problem(problem, in: setup))
                    .font(.subheadline)
                    .foregroundStyle(.jovra(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.x2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.jovra(.attentionFill), in: RoundedRectangle(cornerRadius: Radius.control + 2, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("record.problems")
    }

    private func actions(ready: Bool) -> some View {
        VStack(spacing: Space.x1) {
            Button {
                store.checkCameraPosition(router)
            } label: {
                Label(SetupCopy.checkCameraPosition, systemImage: "chevron.right")
                    .labelStyle(TrailingIconLabelStyle())
            }
            .buttonStyle(.jovraPrimary)
            .disabled(!ready)
            .accessibilityIdentifier("record.checkCameraPosition")
            Button(SetupCopy.importInstead) { router.show(.push(.sessions(.importVideos))) }
                .font(.body.weight(.medium))
                .foregroundStyle(.jovra(.textPrimary))
                .underline()
                .frame(minHeight: HitTarget.minimum)
                .accessibilityIdentifier("record.importInstead")
        }
        .padding(.top, Space.x1)
    }
}

/// Microphone on or off, as a shape as well as a word.
private struct MicrophoneSymbol: View {
    var isOn: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if !dynamicTypeSize.isAccessibilitySize {
            Image(systemName: isOn ? "mic" : "mic.slash")
                .font(.title3)
                .foregroundStyle(.jovra(.textPrimary))
                .frame(width: 32)
                .accessibilityHidden(true)
        }
    }
}

/// The camera presets this device can record: the fixture clip's format on the simulator, else the
/// back camera's own formats (ultra-wide preferred).
enum CameraFormatSource {
    static func load() async -> [CaptureFormatOption] {
        #if targetEnvironment(simulator)
        guard let clip = Bundle.main.url(forResource: "fixture-camera-720p30", withExtension: "mp4") else { return [] }
        return (try? await CaptureFormatCatalog.fixture(clip)) ?? []
        #else
        return await Task.detached { CaptureFormatCatalog.supported(by: CaptureFormatCatalog.liveCapabilities()) }.value
        #endif
    }
}
