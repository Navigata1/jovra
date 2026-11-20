import JovraCore
import SwiftUI
import UIKit

/// Screen 7's processing half (S07, T27): the saved video, the stage timeline (Saved locally, Preparing
/// replay, Analyzing points, Backing up), the reassurance that the recording is safe, View session as
/// soon as the original is saved, and pause, resume or retry for analysis. Reached after capture or
/// import; in the demo it shows a labelled "Demo processing state" and runs nothing.
struct ProcessingScreen: View {
    nonisolated static let isPlaceholder = false
    var session: SessionID

    @Environment(AppRouter.self) private var router
    @Environment(\.launchConfiguration) private var launch
    @Environment(\.localCaptureLibrary) private var library
    @State private var model = ProcessingScreenModel()
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.system

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CloseControl(label: AppDestination.fullScreen(.processing(session)).info.closeLabel ?? "",
                             identifier: "processing.close") { router.dismissFullScreen() }
                Spacer()
                JovraLockup(height: 28).accessibilityHidden(true)
            }
            .padding(.horizontal, Space.x2).padding(.vertical, Space.x1)
            ScrollView {
                ReadableColumn {
                    VStack(alignment: .leading, spacing: Space.x3) {
                        header
                        if launch.demo != .off {
                            DemoProcessingState()
                        } else {
                            content
                        }
                    }
                    .padding(.horizontal, Space.screenMargin)
                    .padding(.bottom, Space.x4)
                }
            }
            .scrollIndicators(.hidden)
            .clipped()
            .accessibilityIdentifier("processing.scroll")
        }
        .background(Color.jovra(.background).ignoresSafeArea())
        // Capture and Replay force dark, and SwiftUI keeps a forced scheme after that view goes, so this
        // screen states the player's own appearance explicitly.
        .preferredColorScheme(appearance.colorScheme ?? Self.systemColorScheme)
        .task(id: session) {
            guard launch.demo == .off else { return }
            await model.open(session, library: library)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.half) {
            Text(AppDestination.fullScreen(.processing(session)).info.title)
                .jovraDisplayTitle()
                // One long word: at the largest text sizes it shrinks to fit rather than run off-screen.
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("screen.title")
            Text("Your video is saved first. JOVRA does the rest.", tableName: "Processing")
                .font(.jovraSubtitle)
                .foregroundStyle(.jovra(.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView(String(localized: "Opening your session…", table: "Processing"))
                .frame(maxWidth: .infinity, minHeight: 120)
        case .missing:
            StateCard(symbol: "questionmark.folder",
                      title: String(localized: "This session is not on this iPhone", table: "Processing"),
                      message: String(localized: "It may have been deleted. Nothing is processing for it.", table: "Processing"),
                      primaryAction: .init(title: String(localized: "Back to sessions", table: "Processing")) {
                          router.show(.tab(.sessions))
                      })
            .accessibilityIdentifier("processing.missing")
        case .unavailable:
            StateCard(symbol: "externaldrive.badge.exclamationmark",
                      title: String(localized: "Local library unavailable", table: "Processing"),
                      message: String(localized: "Close JOVRA and open it again. Your videos are not removed.", table: "Processing"))
        case .ready(let document):
            ready(document)
        }
    }

    @ViewBuilder private func ready(_ document: SessionDocument) -> some View {
        let scheduler = ProcessingScheduler.shared
        let job = scheduler.job(session)
        let viewable = ProcessingStagePresentation.isViewable(document.original)
        SessionVideoCard(document: document, thumbnail: model.thumbnail, viewable: viewable) { openReplay() }
        VStack(alignment: .leading, spacing: Space.x2) {
            SectionHeader(title: String(localized: "Analysis progress", table: "Processing"))
            VStack(alignment: .leading, spacing: Space.x3) {
                StageTimeline(rows: ProcessingStagePresentation.rows(
                    original: document.original, recordingMode: document.recording.mode, job: job, hold: scheduler.hold))
                if viewable {
                    InfoCard(symbol: "checkmark.shield.fill",
                             title: String(localized: "Recording is safe.", table: "Processing"),
                             message: String(localized: "You can leave this screen.", table: "Processing"),
                             tone: .positive)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("processing.safe")
                }
            }
            .jovraCard(padding: Space.x2 + Space.half)
        }
        VStack(spacing: Space.x1 + Space.half) {
            Button { openReplay() } label: {
                Label { Text("View session", tableName: "Processing") } icon: { Image(systemName: "arrow.right") }
                    .labelStyle(TrailingIconLabelStyle())
            }
            .buttonStyle(.jovraPrimary)
            .disabled(!viewable)
            .accessibilityIdentifier("processing.viewSession")
            analysisAction(job?.analyze)
        }
        StatusStrip(items: statusItems(scheduler: scheduler, analysis: job?.analyze.status))
    }

    @ViewBuilder private func analysisAction(_ stage: ProcessingStageState?) -> some View {
        switch ProcessingStagePresentation.analysisAction(for: stage?.status) {
        case .pause?:
            actionButton(String(localized: "Pause analysis", table: "Processing"), symbol: "pause.fill", id: "processing.pause") {
                await ProcessingScheduler.shared.pauseAnalysis(session)
            }
        case .resume?:
            actionButton(String(localized: "Resume analysis", table: "Processing"), symbol: "play.fill", id: "processing.resume") {
                await ProcessingScheduler.shared.resumeAnalysis(session)
            }
        case .retry?:
            actionButton(String(localized: "Retry analysis", table: "Processing"), symbol: "arrow.clockwise", id: "processing.retry") {
                await ProcessingScheduler.shared.retryAnalysis(session)
            }
        case nil:
            EmptyView()
        }
    }

    private func actionButton(_ title: String, symbol: String, id: String, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(JovraButtonStyle(kind: .secondary, fullWidth: true))
        .accessibilityIdentifier(id)
    }

    /// Wi-Fi policy always; what happens to analysis outside JOVRA only while there is analysis to run.
    private func statusItems(scheduler: ProcessingScheduler, analysis: ProcessingStageState.Status?) -> [StatusStrip.Item] {
        var items = [StatusStrip.Item(id: "wifi", symbol: "wifi",
                                      title: String(localized: "Wi-Fi only", table: "Processing"),
                                      detail: String(localized: "Backup waits for Wi-Fi", table: "Processing"))]
        if let note = ProcessingStagePresentation.backgroundNote(analysis: analysis,
                                                                 continuesInBackground: scheduler.continuesInBackground) {
            items.append(.init(id: "path", symbol: "iphone",
                               title: String(localized: "Runs on this iPhone", table: "Processing"), detail: note))
        }
        return items
    }

    /// The device's own appearance (the screen's traits are not affected by an app's forced scheme).
    private static var systemColorScheme: ColorScheme {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.screen.traitCollection.userInterfaceStyle == .dark ? .dark : .light
    }

    private func openReplay() {
        router.present(.replay(ReplayRequest(session: session, point: nil, filter: .all)))
    }
}

/// The two small facts under the actions ("Wi-Fi only · Backup waits for Wi-Fi").
struct StatusStrip: View {
    struct Item: Identifiable {
        var id: String
        var symbol: String
        var title: String
        var detail: String
    }

    var items: [Item]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.x2))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Space.x2))
        layout {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: Space.x1 + Space.half) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.jovra(.textPrimary))
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.jovraLabel).foregroundStyle(.jovra(.textPrimary))
                        Text(item.detail).font(.jovraCaption).foregroundStyle(.jovra(.textSecondary))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("processing.status.\(item.id)")
            }
        }
        .padding(.top, Space.x1)
    }
}
