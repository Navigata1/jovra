import JovraCore
import JovraMedia
import SwiftUI

/// "● REC 12:46" / "❙❙ Paused 12:46" / "■ Stopped 12:46" over the preview (screen spec S06,
/// RecordingStatusPill). The red dot is never the only signal: the words change with it.
struct RecordingStatusPill: View {
    var state: CaptureRecordingState

    var body: some View {
        HStack(spacing: Space.x1) {
            switch state.pill {
            case .recording:
                Circle().fill(Color.jovra(.recording)).frame(width: 12, height: 12).accessibilityHidden(true)
            case .paused:
                Image(systemName: "pause.fill").accessibilityHidden(true)
            case .stopped:
                Image(systemName: "stop.fill").accessibilityHidden(true)
            }
            Text(verbatim: CaptureRecordingCopy.pillText(state))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.headline)
        .foregroundStyle(.jovra(.textOnEditorial))
        .padding(.horizontal, Space.x2)
        .padding(.vertical, Space.x1 + Space.half)
        .frame(minHeight: HitTarget.minimum)
        .background(Color.jovra(.background), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: CaptureRecordingCopy.pillAccessibilityLabel(state)))
        .accessibilityIdentifier("capture.recPill")
    }
}

/// "78%" with the battery symbol; hidden when iOS does not report a level (the simulator).
struct BatteryPill: View {
    var fraction: Double

    var body: some View {
        let percent = Int((fraction * 100).rounded())
        Label {
            Text(verbatim: JovraFormat.percent(percent))
        } icon: {
            Image(systemName: percent <= 20 ? "battery.25percent" : "battery.75percent").accessibilityHidden(true)
        }
        .font(.subheadline.weight(.semibold).monospacedDigit())
        .foregroundStyle(.jovra(.textOnEditorial))
        .padding(.horizontal, Space.x2)
        .frame(minHeight: HitTarget.minimum)
        .background(Color.jovra(.background), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Battery \(JovraFormat.percent(percent))", tableName: "Capture"))
    }
}

/// A capture control used at arm's length: a 64 pt ring with its symbol and the label under it, or the
/// 76 pt red Stop disc whose label is read but not drawn (screen spec S06, CaptureControlButton).
struct CaptureControlButton: View {
    enum Kind { case ring, stop }

    /// Stop's disc with its halo ring: the tallest control, which the others centre on.
    static let stopDiameter = HitTarget.stop + 2 * Space.half

    var kind: Kind = .ring
    var title: String
    var symbol: String
    var identifier: String
    var action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.x1) {
                disc
                // Beyond the largest standard size the captions would push the controls apart; the
                // Large Content Viewer shows the name instead, and VoiceOver always reads it.
                if kind == .ring, !dynamicTypeSize.isAccessibilitySize {
                    Text(verbatim: title)
                        .font(.jovraLabel)
                        .foregroundStyle(.jovra(isEnabled ? .textOnEditorial : .textSecondaryOnEditorial))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CapturePressStyle())
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityShowsLargeContentViewer { Label(title, systemImage: symbol) }
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder private var disc: some View {
        switch kind {
        case .ring:
            // Unavailable controls keep readable ink and a dashed ring rather than fading out.
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.jovra(isEnabled ? .textOnEditorial : .textSecondaryOnEditorial))
                .frame(width: HitTarget.capture, height: HitTarget.capture)
                .overlay(Circle().strokeBorder(Color.jovra(isEnabled ? .textOnEditorial : .textSecondaryOnEditorial),
                                               style: StrokeStyle(lineWidth: 2.5, dash: isEnabled ? [] : [5, 4])))
        case .stop:
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.jovra(.onRecording))
                .frame(width: 26, height: 26)
                .frame(width: HitTarget.stop, height: HitTarget.stop)
                .background(Color.jovra(.recording), in: Circle())
                .padding(Space.half)
                .overlay(Circle().strokeBorder(Color.jovra(.textOnEditorial).opacity(0.35), lineWidth: 2))
        }
    }
}

/// Pressing dims the control and, unless Reduce Motion is on, scales it slightly.
private struct CapturePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(Motion.standard.animation(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

/// "Video saved on this iPhone" with the durable time under it (user story 74). The time line keeps its
/// own identifier so tests and VoiceOver read the exact saved-through value.
struct CaptureSaveStatus: View {
    var state: CaptureRecordingState

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
            Image(systemName: hasSaved ? "checkmark.circle.fill" : "arrow.down.circle")
                .foregroundStyle(.jovra(hasSaved ? .positiveInk : .textSecondaryOnEditorial))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.half) {
                Text(verbatim: hasSaved ? CaptureRecordingCopy.savedOnDevice : CaptureRecordingCopy.savingFirstSeconds)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.jovra(.textOnEditorial))
                    .fixedSize(horizontal: false, vertical: true)
                if let saved = state.savedThroughMs, saved > 0 {
                    Text(verbatim: CaptureRecordingCopy.savedThrough(saved))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.jovra(.textSecondaryOnEditorial))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One element that ends with the durable time ("…, Saved through 12:44"), read as it changes.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("capture.confirmedTime")
    }

    private var hasSaved: Bool { (state.savedThroughMs ?? 0) > 0 }
}

/// Every recorded gap, in session time ("Gap 0:04–0:09 · interruption").
struct CaptureGapList: View {
    var gaps: [SessionGap]
    var ink: ColorRole = .textSecondaryOnEditorial

    var body: some View {
        if !gaps.isEmpty {
            VStack(alignment: .leading, spacing: Space.half) {
                ForEach(Array(gaps.enumerated()), id: \.offset) { index, gap in
                    CaptureGapRow(text: CaptureRecordingCopy.gap(gap), ink: ink)
                        .accessibilityIdentifier("capture.gap.\(index)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// "Paused · Not recording" (screen spec S06, Paused) or "Stopped · Not recording" across the panel.
struct CaptureNotRecordingBanner: View {
    var text: String
    var symbol: String
    var identifier: String

    static var paused: Self { .init(text: CaptureRecordingCopy.pausedBanner, symbol: "pause.circle.fill", identifier: "capture.pausedBanner") }
    static var stopped: Self { .init(text: CaptureRecordingCopy.stoppedBanner, symbol: "stop.circle.fill", identifier: "capture.stoppedBanner") }

    var body: some View {
        Label {
            Text(verbatim: text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).accessibilityHidden(true)
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(.jovra(.textOnEditorial))
        .padding(Space.x1 + Space.half)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.jovra(.surfaceSunken), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// One gap line: the scissors mark and its words wrap together at any text size.
struct CaptureGapRow: View {
    var text: String
    var ink: ColorRole

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
            Image(systemName: "scissors").accessibilityHidden(true)
            Text(verbatim: text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
        .foregroundStyle(.jovra(ink))
        .accessibilityElement(children: .combine)
    }
}
