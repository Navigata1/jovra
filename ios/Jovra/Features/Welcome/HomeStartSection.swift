import JovraCore
import OSLog
import SwiftUI

/// What Home shows about how the player started (T18; screens.md S03 States "Sample" and "Empty"): the DemoBanner
/// while the demo profile is in use, or, for a player with no sessions yet, the real empty state. Home's own tiles,
/// latest session and trend belong to T19; this section only decides the demo and first-run states.
struct HomeStartSection: View {
    enum Part {
        /// Above the greeting (S03 layout 2): known from the profile at once, so nothing below it moves.
        case demoBanner
        /// In place of the tiles, latest session and trend, under the editorial card (S03 States "Empty").
        case firstSession
    }

    var part: Part

    @Environment(AppRouter.self) private var router
    @Environment(PlayerProfileModel.self) private var model
    @Environment(\.localCaptureLibrary) private var library
    @State private var problem = false

    var body: some View {
        Group {
            if part == .demoBanner, model.isDemo {
                DemoBanner {
                    model.beginOnboarding()
                    router.show(.preShell(.onboarding(step: 2)))
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("home.demoBanner")
            } else if part == .firstSession, model.isFirstRunEmpty {
                StateCard(symbol: "video",
                          title: String(localized: "Your first session shows up here.", table: "Welcome"),
                          message: String(localized: "Record a match or practice, or import a video you already have.", table: "Welcome"),
                          primaryAction: .init(title: String(localized: "Import a video", table: "Welcome")) {
                              router.show(.push(.sessions(.importVideos)))
                          },
                          // Sample sessions already installed are in Sessions, badged; no second offer.
                          secondaryAction: model.hasSampleContent ? nil
                              : .init(title: String(localized: "Explore the sample", table: "Welcome"), perform: addSample))
                    .accessibilityIdentifier("home.emptyState")
                if problem {
                    BannerView(tone: .attention,
                               title: String(localized: "The sample couldn't be added. Nothing was changed; try again.", table: "Welcome"),
                               message: nil, primaryAction: nil, secondaryAction: nil)
                }
            }
        }
    }

    private func addSample() {
        Task {
            do {
                problem = false
                try await model.installSample(library: library, content: BundledSampleLibrary.load())
            } catch {
                Logger(subsystem: "com.islanddevcrew.jovra", category: "Welcome")
                    .error("The sample could not be added: \(String(describing: error), privacy: .public)")
                problem = true
            }
        }
    }
}
