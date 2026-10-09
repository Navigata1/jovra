import SwiftUI

/// Placeholder for the capability detail sheet (N12; T12 may move it into DesignSystem/Components), handed to T12. T12 replaces this file and keeps
/// `CapabilityDetailSheet(capability:)`, so the router (App/Destinations.swift) never changes.
struct CapabilityDetailSheet: View {
    var capability: CapabilityID

    var body: some View {
        RoutePlaceholder(.sheet(.capabilityDetail(capability)))
    }
}
