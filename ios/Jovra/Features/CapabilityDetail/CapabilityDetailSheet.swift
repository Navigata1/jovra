import SwiftUI

/// The capability detail sheet (N12, "How this was measured"). Every Estimated badge, "Off until it
/// passes testing" note and "Why?" link opens it; its content comes from the capability registry
/// through `CapabilityDetailView` (DesignSystem/Components). The router (App/Destinations.swift)
/// keeps calling `CapabilityDetailSheet(capability:)`.
struct CapabilityDetailSheet: View {
    nonisolated static let isPlaceholder = false
    var capability: CapabilityID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let info = AppDestination.sheet(.capabilityDetail(capability)).info
        VStack(spacing: 0) {
            HStack {
                CloseControl(label: info.closeLabel ?? info.title, identifier: "sheet.close") { dismiss() }
                Spacer()
                JovraLockup(height: 28)
            }
            .padding(.horizontal, Space.x2)
            .padding(.top, Space.x1)
            ScrollView {
                ReadableColumn {
                    VStack(alignment: .leading, spacing: Space.x3) {
                        Text(info.title)
                            .jovraDisplayTitle()
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("screen.title")
                        CapabilityDetailView(capabilityID: capability.rawValue)
                    }
                    .padding(.horizontal, Space.screenMargin)
                    .padding(.top, Space.x2)
                    .padding(.bottom, Space.x4)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.jovra(.background).ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet.container")
    }
}
