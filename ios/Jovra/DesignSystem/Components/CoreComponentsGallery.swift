// l10n-lint: ignore-file (DEBUG-only component gallery for UI tests and screenshots; absent from release builds)
#if DEBUG
import JovraCore
import SwiftUI

/// An opt-in native gallery for component acceptance checks; absent from release builds.
/// `JOVRA_CORE_COMPONENT_GALLERY=<scenario>` replaces the app's root with one scenario.
struct CoreComponentsGalleryHarness: ViewModifier {
    func body(content: Content) -> some View {
        if let rawSource = ProcessInfo.processInfo.environment["JOVRA_VIDEO_LAB"],
           let source = VideoLab.Source(rawValue: rawSource) {
            VideoLab(source: source)
        } else if let rawState = ProcessInfo.processInfo.environment["JOVRA_CORE_COMPONENT_GALLERY"],
           let state = CoreComponentsGallery.Scenario(rawValue: rawState) {
            CoreComponentsGallery(state: state)
        } else {
            content
        }
    }
}

struct CoreComponentsGallery: View {
    enum Scenario: String, CaseIterable {
        case empty, denied, error, unsupported, badges
        case tiles, popover, controls, feedback, chrome, capability
        case capabilityInjected = "capability-injected"
        case art
    }

    enum FractionTile: Identifiable {
        case firstServes, secondServes
        var id: Self { self }
    }

    var state: Scenario
    @State private var actionResult: String?
    @State private var popover: FractionTile?
    @State private var toasts = ToastCenter()
    @State private var backupOn = true
    @State private var cellularOn = false
    @State private var columnWidth: CGFloat = 0
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // As on JovraScreen: the page stops at the status bar, so nothing scrolls behind the clock;
        // at the bottom it runs under the home indicator like any iOS page.
        GeometryReader { proxy in
            page
                .contentMargins(.bottom, proxy.safeAreaInsets.bottom, for: .scrollContent)
                .clipped()
                .padding(.top, proxy.safeAreaInsets.top)
                .ignoresSafeArea(.container, edges: .vertical)
        }
        .background(Color.jovra(.background).ignoresSafeArea())
        .toastHost(toasts)
    }

    private var page: some View {
        ScrollView {
            ReadableColumn {
                VStack(alignment: .leading, spacing: Space.x3) {
                    Text(String(localized: "Core components", table: "DesignSystem.Components"))
                        .font(.jovraHeadline)
                        .foregroundStyle(.jovra(.textPrimary))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityValue(Text(verbatim: contrast == .increased ? "Increased contrast" : "Standard contrast"))
                        .accessibilityIdentifier("screen.title")
                    scenario
                    if let actionResult {
                        Text(actionResult).foregroundStyle(.jovra(.textPrimary)).accessibilityIdentifier("gallery.result")
                    }
                }
                .padding(Space.screenMargin)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { columnWidth = $0 }
            }
        }
    }

    @ViewBuilder private var scenario: some View {
        switch state {
        case .badges: badges
        case .tiles: tiles
        case .popover: inlinePopovers
        case .controls: controls
        case .feedback: feedback
        case .chrome: chrome
        case .capability: capability
        case .capabilityInjected: injectedCapability
        case .art: art
        case .empty, .denied, .error, .unsupported: stateCard
        }
    }

    // MARK: States

    @ViewBuilder private var stateCard: some View {
        switch state {
        case .denied:
            StateCard(symbol: "camera", title: String(localized: "Camera access is off", table: "DesignSystem.Components"),
                      message: String(localized: "Turn on Camera for JOVRA in iOS Settings to record. You can still import videos you already have.", table: "DesignSystem.Components"),
                      primaryAction: .init(title: String(localized: "Open iOS Settings", table: "DesignSystem.Components")) {
                          actionResult = String(localized: "Settings requested", table: "DesignSystem.Components")
                      })
        case .error:
            StateCard(symbol: "exclamationmark.triangle", title: String(localized: "Export didn't finish", table: "DesignSystem.Components"),
                      message: String(localized: "Your video is safe. Try exporting again.", table: "DesignSystem.Components"),
                      primaryAction: .init(title: String(localized: "Retry", table: "DesignSystem.Components")) {
                          actionResult = String(localized: "Retry requested", table: "DesignSystem.Components")
                      })
        case .unsupported:
            StateCard(symbol: "info.circle", title: String(localized: "Speed is not available", table: "DesignSystem.Components"),
                      message: String(localized: "This capability has not passed its checks.", table: "DesignSystem.Components"))
        default:
            StateCard(
                symbol: "tray",
                title: String(localized: "No sessions yet", table: "DesignSystem.Components"),
                message: String(localized: "Record a match or practice, or import a video you already have.", table: "DesignSystem.Components"),
                primaryAction: .init(title: String(localized: "Record a session", table: "DesignSystem.Components")) {
                    actionResult = String(localized: "Record requested", table: "DesignSystem.Components")
                },
                secondaryAction: .init(title: String(localized: "Import a video", table: "DesignSystem.Components")) {
                    actionResult = String(localized: "Import requested", table: "DesignSystem.Components")
                }
            )
        }
    }

    private var badges: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            SampleBadge().accessibilityIdentifier("gallery.sample")
            SampleBadge(size: .small)
            FixtureBadge().accessibilityIdentifier("gallery.fixture")
            ForEach([Provenance.manual, .estimated, .reviewed, .validated], id: \.self) {
                ProvenanceBadge(kind: .provenance($0), size: .small)
            }
            EditorialCard {
                SampleBadge(onForest: true)
                ProvenanceBadge(kind: .provenance(.estimated), onForest: true)
            }
            DemoBanner { actionResult = String(localized: "Onboarding requested", table: "DesignSystem.Components") }
        }
    }

    /// Values here are fixed illustrations for component checks, said so on screen (CLAUDE.md rule 1).
    private var illustrationNote: some View {
        let layout = stackingLayout(spacing: Space.x1, alignment: .center)
        return layout {
            SampleBadge(size: .small)
            Text("Illustrative values for component checks")
                .font(.footnote)
                .foregroundStyle(.jovra(.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Tiles and the fraction popover

    private var firstServes: FractionPresentation {
        // 40 of 60 through the engine's own rounding rule (ADR-0011).
        FractionPresentation(ratio: (try? Percent.ratio(n: 40, d: 60)) ?? RateRatio(n: 0, d: 0, pct: .null, display: "—"), provenance: .manual)
    }

    private var secondServes: FractionPresentation {
        FractionPresentation(ratio: (try? Percent.ratio(n: 0, d: 0)) ?? RateRatio(n: 0, d: 0, pct: .null, display: "—"), provenance: .manual)
    }

    private var tiles: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            illustrationNote
            SectionHeader(title: "Standard tiles")
            tileRow {
                StatTile(value: "8", label: "Sessions", symbol: "tennisball", badge: .sample)
                StatTile(label: "First serves in", fraction: firstServes, symbol: "scope", scope: "Latest match") {
                    popover = .firstServes
                }
                .accessibilityIdentifier("tile.firstServes")
                .fractionPopover(isPresented: binding(.firstServes)) {
                    FractionPopover(label: "First serves in", fraction: firstServes,
                                    definition: "First serves that landed in, out of every first serve you hit.") {
                        popover = nil
                        actionResult = "Show points requested"
                    }
                }
            }
            SectionHeader(title: "Compact tiles")
            tileRow {
                StatTile(value: "124", label: "Points", symbol: "tennisball", compact: true)
                StatTile(label: "Second serves won", fraction: secondServes, symbol: "scope", compact: true) {
                    popover = .secondServes
                }
                .accessibilityIdentifier("tile.secondServes")
                .fractionPopover(isPresented: binding(.secondServes)) {
                    FractionPopover(label: "Second serves won", fraction: secondServes,
                                    definition: "Points won when your second serve was in play. No second serves were recorded.")
                }
            }
        }
    }

    /// The popover's content inline, so the accessibility audit can reach it: XCUITest reports a
    /// presented popover's window with an empty visible frame and cannot attribute its text.
    private var inlinePopovers: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            illustrationNote
            FractionPopover(label: "First serves in", fraction: firstServes,
                            definition: "First serves that landed in, out of every first serve you hit.",
                            showPoints: { actionResult = "Show points requested" }, scrollsAtAccessibilitySizes: false)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            FractionPopover(label: "Second serves won", fraction: secondServes,
                            definition: "Points won when your second serve was in play. No second serves were recorded.",
                            scrollsAtAccessibilitySizes: false)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }

    private func binding(_ tile: FractionTile) -> Binding<Bool> {
        Binding(get: { popover == tile }, set: { if !$0 { popover = nil } })
    }

    /// Side by side, stacked at accessibility sizes. One set of views whose layout changes, so text
    /// keeps scaling (ViewThatFits would swap in a second copy as the text grows).
    private func tileRow(@ViewBuilder _ content: () -> some View) -> some View {
        let layout = stackingLayout(spacing: Space.x1)
        return layout { content() }
            .fixedSize(horizontal: false, vertical: true)
    }

    private func stackingLayout(spacing: CGFloat, alignment: VerticalAlignment = .top) -> AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: alignment, spacing: spacing))
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Button("Record a session") { actionResult = "Accent tapped" }.buttonStyle(.jovraAccent)
            Button("Continue") { actionResult = "Primary tapped" }.buttonStyle(.jovraPrimary)
            Button("Pause analysis") { actionResult = "Secondary tapped" }.buttonStyle(.jovraSecondary)
            HStack(spacing: Space.x1) {
                Button("Save clip") { actionResult = "Compact tapped" }.buttonStyle(JovraButtonStyle(kind: .primary, size: .compact))
                Button("Review placements") { actionResult = "Compact secondary tapped" }.buttonStyle(.jovraCompact)
            }
            EditorialCard {
                Text("Ready for your next session?").font(.jovraHeadline).foregroundStyle(.jovra(.textOnEditorial))
                Button("Not now") { actionResult = "On-forest tapped" }.buttonStyle(.jovraOnForestSecondary)
            }
            VStack(alignment: .leading, spacing: Space.x1) {
                StatusPill(text: "On device · Backed up", tone: .positive)
                StatusPill(text: "Needs review", tone: .attention)
                StatusPill(text: "Queued", tone: .neutral)
                StatusPill(text: "Uploading 62%", tone: .inProgress, progress: 0.62)
                StatusPill(text: "On this iPhone", tone: .neutral, symbol: "iphone")
            }
            VStack(spacing: 0) {
                SettingsRow(symbol: "camera", title: "Camera", subtitle: "Allowed")
                Divider()
                ToggleRow(symbol: "icloud.and.arrow.up", title: "Back up to Google Drive",
                          description: "Copies finished sessions to your own Drive.", isOn: $backupOn)
                Divider()
                ToggleRow(title: "Use cellular data", description: "Off: backups wait for Wi-Fi.", isOn: $cellularOn)
                Divider()
                SettingsRow(symbol: "trash", title: "Delete all JOVRA data", isDestructive: true)
            }
            .jovraCard()
        }
    }

    // MARK: Feedback

    private var feedback: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            BannerView(tone: .attention, title: "Backup didn't finish",
                       message: "Your video is safe on this iPhone. JOVRA will try again on Wi-Fi.",
                       primaryAction: .init(title: "Retry backup") { actionResult = "Retry backup requested" },
                       secondaryAction: .init(title: "Details") { actionResult = "Details requested" })
            BannerView(tone: .positive, title: "Recording recovered", message: "12:46 of video was saved before the app closed.")
            BannerView(tone: .info, title: "Score and stats updated")
            InfoCard(symbol: "lock.shield", title: "Your video stays on this iPhone",
                     message: "Nothing is uploaded unless you turn on backup.", tone: .positive)
            InfoCard(symbol: "bolt.horizontal", title: "Analysis runs on power", message: "Long sessions process overnight while charging.")
            Button("Show toast") { toasts.show("Score updated for points 43–124") }
                .buttonStyle(.jovraSecondary)
            Button("Move to Recently deleted") {
                toasts.show("Moved to Recently deleted") { actionResult = "Restored" }
            }
            .buttonStyle(.jovraSecondary)
        }
    }

    // MARK: Chrome

    private var chrome: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            FocusedHeader(title: "Jon vs Alex · Point 42", closeLabel: "Close replay") {
                actionResult = "Close requested"
            } trailing: {
                Button { actionResult = "More requested" } label: {
                    Image(systemName: "ellipsis").frame(width: HitTarget.minimum, height: HitTarget.minimum)
                }
                .foregroundStyle(.jovra(.textPrimary))
                .accessibilityLabel("More")
            }
            .jovraCard(padding: 0)
            VStack(alignment: .leading, spacing: Space.x1) {
                Text("This page sits in a readable column: full width on iPhone, at most 720 points on iPad.")
                    .font(.jovraBody)
                    .foregroundStyle(.jovra(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                // The measured width of this page's ReadableColumn, read by the layout UI test.
                Text("Column width: \(Int(columnWidth.rounded())) pt")
                    .font(.jovraTimecode)
                    .foregroundStyle(.jovra(.textPrimary))
                    .accessibilityIdentifier("gallery.columnWidth")
            }
            .jovraCard()
        }
    }

    // MARK: Capability detail

    private var capability: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            CapabilityDetailView(capabilityID: "serveSpeed.manualAssisted")
        }
    }

    /// The same view with a registry injected in place of the bundled one: serve speed validated by a
    /// recorded benchmark. Proves the page reads the registry, not hard-coded text.
    private var injectedCapability: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            BannerView(tone: .info, title: "Injected test registry",
                       message: "Serve speed shows as validated by a test benchmark, so the page is read from the registry.")
            CapabilityDetailView(capabilityID: "serveSpeed.manualAssisted")
                .environment(\.capabilityRegistry, Self.injectedRegistry)
        }
    }

    static let injectedRegistry: CapabilityRegistry? = {
        guard var registry = try? CapabilityRegistry.bundled(),
              let index = registry.capabilities.firstIndex(where: { $0.id == "serveSpeed.manualAssisted" }) else { return nil }
        registry.capabilities[index].status = .validated
        registry.capabilities[index].lastBenchmark = .init(.init(
            runId: "gallery-test", at: "2027-03-02T10:00:00Z", dataset: "Test dataset: radar-paired serves",
            passed: true, results: [.init(name: "Mean absolute error", value: "3.1 mph")]))
        return registry
    }()

    // MARK: Art

    private var art: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            EditorialCard {
                Text("Ready for your next session?")
                    .font(.jovraEditorial)
                    .foregroundStyle(.jovra(.textOnEditorial))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Record a session") { actionResult = "Record requested" }.buttonStyle(.jovraAccent)
            }
            CourtHeroArt(emphasis: .feature)
                .frame(height: 200)
                .background(Color.jovra(.courtSurface), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }
}

#Preview("Core empty") { CoreComponentsGallery(state: .empty) }
#Preview("Core tiles") { CoreComponentsGallery(state: .tiles) }
#Preview("Core feedback dark") { CoreComponentsGallery(state: .feedback).preferredColorScheme(.dark) }
#endif
