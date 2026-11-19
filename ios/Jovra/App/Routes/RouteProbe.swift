import SwiftUI

extension View {
    /// DEBUG only, and only when a UI test launches with `JOVRA_ROUTE_PROBE=1`: exposes the presented
    /// full-screen route's payload (its canonical JSON) as the value of an element named `route.payload`,
    /// so a UI test can assert what the router presented, not only what the screen chose to draw.
    @ViewBuilder func routeProbe(_ route: FullScreenRoute) -> some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["JOVRA_ROUTE_PROBE"] == "1" {
            overlay(alignment: .bottomTrailing) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel(Text(verbatim: "route payload"))
                    .accessibilityValue(Text(verbatim: RouteCoding.key(route)))
                    .accessibilityIdentifier("route.payload")
            }
        } else {
            self
        }
        #else
        self
        #endif
    }
}
