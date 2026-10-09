import SwiftUI

/// The stand-in every unbuilt destination renders until its ticket replaces the file in its feature
/// folder. It says plainly that the screen is a placeholder, names the ticket that builds it, and
/// lists the payload it was opened with, so a route can be checked end to end before its screen exists.
struct RoutePlaceholder: View {
    var destination: AppDestination

    init(_ destination: AppDestination) {
        self.destination = destination
    }

    var body: some View {
        switch destination.info.kind {
        case .fullScreen: FullScreenPlaceholder(destination: destination)
        case .sheet: SheetPlaceholder(destination: destination)
        case .preShell: PreShellPlaceholder(destination: destination)
        case .push, .tab: PushPlaceholder(destination: destination)
        }
    }
}

/// Title, ticket, the "coming later" card and the payload, shared by every placeholder.
private struct PlaceholderBody: View {
    var destination: AppDestination

    var body: some View {
        let info = destination.info
        VStack(alignment: .leading, spacing: Space.x3) {
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(info.title)
                    .jovraDisplayTitle()
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("screen.title")
                Label {
                    Text("Built in ticket \(info.ticket)", tableName: "App", comment: "Placeholder: the ticket that builds this screen, e.g. T28")
                } icon: {
                    Image(systemName: "hammer")
                }
                .font(.jovraLabel)
                .foregroundStyle(.jovra(.textSecondary))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("placeholder.ticket")
            }
            ComingLaterCard(
                symbol: "square.dashed",
                message: String(localized: "This screen is a placeholder. The route, its payload and its Close control already work; the screen itself arrives with its ticket.", table: "App")
            )
            let lines = destination.payloadLines
            if !lines.isEmpty {
                VStack(alignment: .leading, spacing: Space.x1) {
                    Text("Opened with", tableName: "App", comment: "Placeholder: heading over the route's payload")
                        .font(.jovraHeadline)
                        .foregroundStyle(.jovra(.textPrimary))
                        .accessibilityAddTraits(.isHeader)
                    ForEach(lines, id: \.self) { line in
                        Text(line)
                            .font(.jovraBody)
                            .foregroundStyle(.jovra(.textSecondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .jovraCard(padding: Space.x3)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("placeholder.payload")
            }
        }
        .padding(.horizontal, Space.screenMargin)
        .padding(.bottom, Space.x4)
        .frame(maxWidth: 720, alignment: .leading)
        .frame(maxWidth: .infinity)
    }
}

/// A focused flow: forest in every appearance (screen spec §0.5), no tab bar, and a Close control at
/// top leading, at least 44 pt, labelled "Close <screen>" (§0.1).
struct FullScreenPlaceholder: View {
    var destination: AppDestination
    @Environment(AppRouter.self) private var router

    var body: some View {
        let info = destination.info
        VStack(spacing: 0) {
            HStack {
                CloseControl(label: info.closeLabel ?? info.title, identifier: "\(info.launchName).close") {
                    router.dismissFullScreen()
                }
                Spacer()
            }
            .padding(.horizontal, Space.x2)
            .padding(.vertical, Space.x1)
            ScrollView {
                PlaceholderBody(destination: destination)
                    .padding(.top, Space.x2)
            }
            .scrollIndicators(.hidden)
            .clipped()
        }
        .background {
            ZStack {
                Color.jovra(.background) // forest: this view always renders in the dark environment
                CourtLinesBackdrop().stroke(Color.jovra(.textOnEditorial).opacity(0.12), lineWidth: 2)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
        .preferredColorScheme(.dark)
    }
}

/// A sheet: a Close control at top leading, then the placeholder.
struct SheetPlaceholder: View {
    var destination: AppDestination
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let info = destination.info
        VStack(spacing: 0) {
            HStack {
                CloseControl(label: info.closeLabel ?? info.title, identifier: "sheet.close") { dismiss() }
                Spacer()
            }
            .padding(.horizontal, Space.x2)
            .padding(.top, Space.x1)
            ScrollView {
                PlaceholderBody(destination: destination)
                    .padding(.top, Space.x1)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.jovra(.background).ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet.container")
    }
}

/// A push: the tab bar stays, and the system Back button returns to the tab's previous screen.
struct PushPlaceholder: View {
    var destination: AppDestination

    var body: some View {
        ScrollView {
            PlaceholderBody(destination: destination)
                .padding(.top, Space.x1)
        }
        .scrollIndicators(.hidden)
        .clipped()
        .background(Color.jovra(.background).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Welcome and onboarding: before the shell, so the placeholder offers the way in.
struct PreShellPlaceholder: View {
    var destination: AppDestination
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                JovraLockup(height: 40)
                PlaceholderBody(destination: destination)
                    .padding(.horizontal, -Space.screenMargin)
                Button(String(localized: "Open the app", table: "App", comment: "Placeholder: leaves welcome or onboarding for the tabs")) {
                    router.enterShell()
                }
                .buttonStyle(.jovraPrimary)
                .accessibilityIdentifier("preShell.continue")
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.vertical, Space.x2)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Color.jovra(.background).ignoresSafeArea())
    }
}

/// The Close control of full-screen routes and sheets: top leading, 44 × 44 pt, labelled with what it
/// closes ("Close replay").
struct CloseControl: View {
    var label: String
    var identifier: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            // A fixed glyph inside a fixed 44 pt disc, as in the system's own close buttons: at AX5 a
            // text-sized glyph would overflow the disc. The Large Content Viewer shows it enlarged.
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: HitTarget.minimum, height: HitTarget.minimum)
                .background(Color.jovra(.surface), in: Circle())
                .overlay(Circle().strokeBorder(Color.jovra(.separator), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.jovra(.textPrimary))
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityShowsLargeContentViewer {
            Label(label, systemImage: "xmark")
        }
        .accessibilityIdentifier(identifier)
    }
}

extension AppDestination {
    /// The payload, one readable line per value (nil values are left out).
    var payloadLines: [String] {
        switch self {
        case .preShell(.welcome), .tab:
            []
        case .preShell(.onboarding(let step)):
            [String(localized: "Step \(step)", table: "App", comment: "Placeholder payload: onboarding step")]
        case .push(.sessions(.importVideos)), .push(.insights(.progress)), .push(.profile):
            []
        case .push(.sessions(.matchOverview(let session))), .push(.sessions(.practiceOverview(let session))):
            [Self.line(session)]
        case .push(.insights(.shotMap(let session))), .push(.insights(.serveLab(let session))),
             .push(.insights(.strokeLab(let session))):
            session.map { [Self.line($0)] } ?? []
        case .push(.insights(.drillDetail(let drill))), .fullScreen(.drillSession(let drill)):
            [String(localized: "Drill: \(drill.rawValue)", table: "App", comment: "Placeholder payload")]
        case .fullScreen(let route):
            route.payloadLines
        case .sheet(let route):
            route.payloadLines
        }
    }

    static func line(_ session: SessionID) -> String {
        String(localized: "Session: \(session.rawValue)", table: "App", comment: "Placeholder payload")
    }

    static func line(_ point: PointID) -> String {
        String(localized: "Point: \(point.rawValue)", table: "App", comment: "Placeholder payload")
    }

    static func line(_ filter: PointFilter) -> String {
        String(localized: "Filter: \(filter.title)", table: "App", comment: "Placeholder payload")
    }

    static func line(_ time: MediaTime) -> String {
        String(localized: "At: \(JovraFormat.clock(seconds: Double(time.wholeSeconds)))", table: "App", comment: "Placeholder payload: a time in the video")
    }
}

private extension FullScreenRoute {
    var payloadLines: [String] {
        switch self {
        case .capture(let setup):
            setup.map { [String(localized: "Session kind: \($0.kind.title)", table: "App", comment: "Placeholder payload")] } ?? []
        case .replay(let request):
            [AppDestination.line(request.session)] + (request.point.map { [AppDestination.line($0)] } ?? [])
                + (request.filter.map { [AppDestination.line($0)] } ?? [])
        case .compare(let comparison):
            comparison.map { [String(localized: "Comparison: \($0.rawValue)", table: "App", comment: "Placeholder payload")] } ?? []
        case .pointReview(let session, let filter):
            [AppDestination.line(session), AppDestination.line(filter)]
        case .highlightReel(let session), .processing(let session):
            [AppDestination.line(session)]
        case .drillSession(let drill):
            [String(localized: "Drill: \(drill.rawValue)", table: "App", comment: "Placeholder payload")]
        }
    }
}

private extension SheetRoute {
    var payloadLines: [String] {
        switch self {
        case .pointEditor(let session, let point), .clipExport(let session, let point):
            [AppDestination.line(session)] + (point.map { [AppDestination.line($0)] } ?? [])
        case .sharePack(let session), .consentAttach(let session):
            [AppDestination.line(session)]
        case .capabilityDetail(let capability):
            [String(localized: "Capability: \(capability.rawValue)", table: "App", comment: "Placeholder payload")]
        case .matchFormat(.sessionSetup):
            [String(localized: "For the session setup", table: "App", comment: "Placeholder payload")]
        case .matchFormat(.session(let session)):
            [AppDestination.line(session)]
        case .goal(let goal):
            goal.map { [String(localized: "Goal: \($0.rawValue)", table: "App", comment: "Placeholder payload")] } ?? []
        case .calibration(let session, let time), .stringBroke(let session, let time):
            [AppDestination.line(session), AppDestination.line(time)]
        case .restore(let session):
            session.map { [AppDestination.line($0)] } ?? []
        case .players, .cameraPreset, .trash, .comparisonPicker, .driveAccount, .account, .deleteAllData, .permission:
            []
        }
    }
}
