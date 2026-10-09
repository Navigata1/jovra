import SwiftUI

/// Placeholder for the goal sheet (S16), handed to T48. T48 replaces this file and keeps
/// `GoalSheet(goal:)`, so the router (App/Destinations.swift) never changes.
struct GoalSheet: View {
    var goal: GoalID?

    var body: some View {
        RoutePlaceholder(.sheet(.goal(goal)))
    }
}
