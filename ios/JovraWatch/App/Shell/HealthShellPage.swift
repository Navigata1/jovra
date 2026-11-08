import JovraRoom
import SwiftUI

/// Camera health in the shell (reference 61): the fresh-and-recording count over the roster, its basis, the worst
/// three cameras and "View all". W04 replaces this page with the full surface (HealthSummary, slots, flags).
struct HealthShellPage: View {
    let model: WatchAppModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        WatchPage(surface: .health, isSample: model.isSample) {
            if let snapshot = model.snapshot, let board = model.receiver.board {
                headline(board.counts, policy: snapshot.freshnessPolicy.policy)
                if model.receiver.isAwaitingLiveUpdate { awaitingBanner }
                ForEach(Array(WatchStatusText.worstFirst(board.rows).prefix(3)), id: \.deviceId) { row in
                    CameraRowView(row: row)
                }
                if board.counts.enrolled > 3 {
                    NavigationLink(value: WatchRoute.cameras) {
                        Label {
                            Text("View all \(board.counts.enrolled)", tableName: "Watch")
                        } icon: {
                            Image(systemName: "arrow.right")
                        }
                        .labelStyle(TrailingIconLabelStyle())
                    }
                    .buttonStyle(WatchPrimaryButtonStyle())
                    .accessibilityIdentifier("watch.health.viewAll")
                }
            } else {
                WatchStatePanel(symbol: "iphone",
                                title: Text("Waiting for your phone", tableName: "Watch"),
                                message: Text("Open JOVRA on your iPhone. Camera status appears here.",
                                              tableName: "Watch"))
                    .accessibilityIdentifier("watch.waiting")
            }
        }
    }

    private func headline(_ counts: RoomCounts, policy: FreshnessPolicy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                WatchHeroNumber(value: "\(counts.freshRecording)/\(counts.enrolled)")
                Text("fresh", tableName: "Watch")
                    .font(.watchTitle)
                    .foregroundStyle(WatchPalette.ivory)
            }
            Text("Recording, heard in the last \(policy.freshMaxMs / 1000)\u{00A0}s", tableName: "Watch")
                .font(.watchCaption)
                .foregroundStyle(WatchPalette.secondaryText(contrast))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(counts.freshRecording) of \(counts.enrolled) cameras fresh and recording.",
                                 tableName: "Watch"))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("watch.health.headline")
    }

    private var awaitingBanner: some View {
        WatchCard {
            HStack(alignment: .top, spacing: 8) {
                FreshnessMark(freshness: .unknown).padding(.top, 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Waiting for a live update", tableName: "Watch")
                        .font(.watchBody.weight(.semibold))
                        .foregroundStyle(WatchPalette.clayInk)
                    Text("Cameras stay Unknown until your phone answers.", tableName: "Watch")
                        .font(.watchCaption)
                        .foregroundStyle(WatchPalette.secondaryText(contrast))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("watch.health.awaitingLiveUpdate")
    }
}

/// One camera: short name, the frozen elapsed time or a state word, a freshness shape and the last-heard age.
struct CameraRowView: View {
    let row: StatusRow
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        WatchCard {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(spacing: 6))
            layout {
                Text(verbatim: WatchStatusText.shortName(row.deviceId))
                    .font(.watchBody.weight(.bold))
                    .foregroundStyle(WatchPalette.ivory)
                Text(verbatim: WatchStatusText.value(row))
                    .font(.watchValue)
                    .foregroundStyle(row.stale ? (row.freshness == .unknown ? WatchPalette.clayInk : WatchPalette.ivory)
                                               : WatchPalette.ivory)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 2) }
                HStack(spacing: 4) {
                    FreshnessMark(freshness: row.freshness)
                    Text(verbatim: WatchStatusText.shortAge(row) ?? "–")
                        .font(.watchCaption.monospacedDigit())
                        .foregroundStyle(row.freshness == .unknown ? WatchPalette.clayInk
                                                                   : WatchPalette.secondaryText(contrast))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: WatchStatusText.spokenRow(row)))
        .accessibilityIdentifier("watch.camera.\(row.deviceId)")
    }
}

/// "View all n": every camera, worst first.
struct CameraListView: View {
    let model: WatchAppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(WatchStatusText.worstFirst(model.receiver.board?.rows ?? []), id: \.deviceId) {
                    CameraRowView(row: $0)
                }
                if model.isSample { SampleTag().padding(.top, 2) }
            }
        }
        .navigationTitle(Text("Cameras", tableName: "Watch"))
        .containerBackground(WatchPalette.background, for: .navigation)
        .accessibilityIdentifier("watch.cameras")
    }
}

/// Title then icon, for "View all 6 →".
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon.accessibilityHidden(true)
        }
    }
}
