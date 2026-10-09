import SwiftUI

/// Placeholder for the player onboarding (S02), handed to T18. T18 replaces this file and keeps
/// `OnboardingScreen(step:)`, so the router (App/Destinations.swift) never changes.
struct OnboardingScreen: View {
    var step: Int

    var body: some View {
        RoutePlaceholder(.preShell(.onboarding(step: step)))
    }
}
