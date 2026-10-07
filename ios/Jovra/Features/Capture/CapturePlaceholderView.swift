import SwiftUI

/// Stand-in for the capture flow, presented as a full-screen route with no tab bar.
/// Focused video screens are forest in every appearance.
struct CapturePlaceholderView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                JovraLockup(height: 32, markColor: .jovra(.textOnEditorial), tennisColor: .jovra(.accent))
                Spacer()
                Button { router.dismissFullScreen() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: HitTarget.minimum, height: HitTarget.minimum)
                        .background(Color.jovra(.surface), in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.jovra(.textPrimary))
                .accessibilityLabel("Close")
                .accessibilityIdentifier("capture.close")
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.vertical, Space.x1)

            ScrollView {
                VStack(alignment: .leading, spacing: Space.x3) {
                    Text("Frame your court")
                        .jovraDisplayTitle()
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("capture.title")
                    ComingLaterCard(
                        symbol: "camera.viewfinder",
                        message: "Court framing, calibration and recording arrive in a later ticket. Video will be saved on this device before any analysis runs."
                    )
                    Button("Done") { router.dismissFullScreen() }
                        .buttonStyle(JovraButtonStyle(kind: .accent, fullWidth: true))
                }
                .padding(.horizontal, Space.screenMargin)
                .padding(.top, Space.x5)
                .padding(.bottom, Space.x3)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
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
        // Scoped to this presentation: forest content and a light status bar in every appearance.
        .preferredColorScheme(.dark)
    }
}
