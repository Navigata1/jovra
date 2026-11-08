import ActivityKit
import SwiftUI
import WidgetKit

/// T60 SPIKE (throwaway branch). Brand colours from design-reference/brief/brand-decision.md (BrandPalette).
private enum Palette {
    static let forest = Color(red: 0x09 / 255, green: 0x2A / 255, blue: 0x25 / 255)
    static let forestPanel = Color(red: 0x12 / 255, green: 0x3C / 255, blue: 0x33 / 255)
    static let ivory = Color(red: 0xF4 / 255, green: 0xF1 / 255, blue: 0xE8 / 255)
    static let chartreuse = Color(red: 0xD7 / 255, green: 0xF5 / 255, blue: 0x6A / 255)
}

@main
struct JovraLiveActivityBundle: WidgetBundle {
    var body: some Widget { RecordingLiveActivityWidget() }
}

struct RecordingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            RecordingStatusView(state: context.state, isStale: context.isStale, isSample: context.attributes.isSample)
                .activityBackgroundTint(Palette.forest)
                .activitySystemActionForegroundColor(Palette.ivory)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { PhaseBadge(phase: context.state.phase, isStale: context.isStale) }
                DynamicIslandExpandedRegion(.trailing) {
                    if !context.isStale { RecordingTime(state: context.state).font(.title3.monospacedDigit().weight(.semibold)) }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DetailLine(state: context.state, isStale: context.isStale, isSample: context.attributes.isSample)
                }
            } compactLeading: {
                PhaseDot(phase: context.state.phase, isStale: context.isStale)
            } compactTrailing: {
                if context.isStale { Image(systemName: "questionmark").accessibilityLabel("Status unknown") }
                else { RecordingTime(state: context.state).monospacedDigit().frame(maxWidth: 52) }
            } minimal: {
                PhaseDot(phase: context.state.phase, isStale: context.isStale)
            }
        }
        .supplementalActivityFamilies([.small, .medium])
    }
}

/// Lock Screen / Notification Centre banner, and (small family) the Watch Smart Stack and CarPlay.
struct RecordingStatusView: View {
    let state: RecordingActivityAttributes.ContentState
    let isStale: Bool
    let isSample: Bool
    @Environment(\.activityFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: family == .small ? 2 : 6) {
            HStack(alignment: .firstTextBaseline) {
                PhaseBadge(phase: state.phase, isStale: isStale)
                if !isStale {
                    RecordingTime(state: state).font((family == .small ? Font.headline : .title2).monospacedDigit().weight(.semibold))
                }
                Spacer(minLength: 4)
                if family != .small {
                    Text("JOVRA").font(.caption.weight(.heavy)).tracking(2).foregroundStyle(Palette.ivory.opacity(0.7))
                        .accessibilityHidden(true)
                }
            }
            DetailLine(state: state, isStale: isStale, isSample: isSample)
        }
        .foregroundStyle(Palette.ivory)
        .padding(family == .small ? 8 : 16)
        .accessibilityElement(children: .combine)
    }
}

private struct PhaseBadge: View {
    let phase: RecordingActivityAttributes.Phase
    let isStale: Bool
    var body: some View {
        HStack(spacing: 6) {
            PhaseDot(phase: phase, isStale: isStale)
            Text(title).font(.headline.weight(.bold))
        }
    }
    private var title: String {
        if isStale { return "Status unknown" }
        switch phase {
        case .recording: return "REC"
        case .paused: return "Paused"
        case .saved: return "Saved"
        }
    }
}

private struct PhaseDot: View {
    let phase: RecordingActivityAttributes.Phase
    let isStale: Bool
    var body: some View {
        Group {
            if isStale { Circle().strokeBorder(Palette.ivory, lineWidth: 2) }
            else if phase == .recording { Circle().fill(Palette.chartreuse) }
            else { Circle().strokeBorder(Palette.chartreuse, lineWidth: 2) }
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }
}

/// Counts REC time on the system clock, so no update is needed per second.
private struct RecordingTime: View {
    let state: RecordingActivityAttributes.ContentState
    var body: some View {
        if state.phase == .recording, let end = state.timerEnd, end > state.recordingStartedAt {
            // Counts on the system clock but stops at the heartbeat deadline (T60 mitigation).
            Text(timerInterval: state.recordingStartedAt...end, countsDown: false)
        } else if state.phase == .recording {
            Text(state.recordingStartedAt, style: .timer)
        } else {
            Text(Duration.seconds(state.recordingSeconds), format: .time(pattern: .minuteSecond))
        }
    }
}

private struct DetailLine: View {
    let state: RecordingActivityAttributes.ContentState
    let isStale: Bool
    let isSample: Bool
    var body: some View {
        if isStale {
            Text("No update from JOVRA for 10 s. Open JOVRA to check the recording.")
                .font(.subheadline).foregroundStyle(Palette.ivory.opacity(0.85))
        } else {
            HStack(spacing: 6) {
                if let savedAt = state.savedAt {
                    Text("Saved \(Text(savedAt, style: .relative)) ago")
                } else {
                    Text("Not saved yet")
                }
                Text("·").accessibilityHidden(true)
                if let battery = state.batteryPercent { Text("Battery \(battery)%") } else { Text("Battery unknown") }
                if isSample {
                    Text("Sample").font(.caption.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Palette.forestPanel, in: Capsule())
                }
            }
            .font(.subheadline).foregroundStyle(Palette.ivory.opacity(0.85)).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}
