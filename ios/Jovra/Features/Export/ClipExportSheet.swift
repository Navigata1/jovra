import JovraMedia
import SwiftUI

/// Foreground local export of one complete segment or a range inside it. Shared-store ACK
/// precedes Done and native sharing; Photos, background recovery and Share Packs are separate.
struct ClipExportSheet: View {
    nonisolated static let isPlaceholder = false
    var session: SessionID
    var point: PointID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.localCaptureLibrary) private var library
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = NativeExportModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CloseControl(label: String(localized: "Close clip export", table: "Export"), identifier: "sheet.close") { dismiss() }
                    .disabled(model.isWorking)
                Spacer(); JovraLockup(height: 28)
            }.padding(Space.x2)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x2) {
                    Text("Clip export", tableName: "Export").jovraDisplayTitle()
                        .accessibilityAddTraits(.isHeader).accessibilityIdentifier("screen.title")
                    Text("One clip and your match data, saved on this iPhone.", tableName: "Export")
                        .font(.jovraBody).fixedSize(horizontal: false, vertical: true)
                    if model.document?.sample != nil { SampleBadge() }
                    controls
                    Button(String(localized: "Create export", table: "Export")) { Task { await model.export() } }
                        .buttonStyle(.jovraPrimary).disabled(!model.canExport).accessibilityIdentifier("export.create")
                    if model.isWorking {
                        ProgressView()
                        Text(model.document == nil ? String(localized: "Opening session…", table: "Export") : String(localized: "Preparing files. Keep JOVRA open until they're saved.", table: "Export"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let error = model.error {
                        StateCard(symbol: "exclamationmark.triangle", title: String(localized: "Export unavailable", table: "Export"), message: error)
                    } else if case .unavailable = library {
                        Text("Local storage is unavailable. Reopen JOVRA to try again.", tableName: "Export")
                    }
                    if let package = model.package { done(package) }
                }.padding(.horizontal, Space.screenMargin).padding(.bottom, Space.x4)
                    .frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
            }.clipped().scrollDismissesKeyboard(.interactively)
        }
        .background(Color.jovra(.background).ignoresSafeArea())
        .interactiveDismissDisabled(model.isWorking)
        .task(id: session) { if case .ready(let library) = library { await model.open(library: library, session: session) } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !model.isWorking { Task { await model.refreshCurrentVersion() } }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            if !model.segments.isEmpty {
                Menu {
                    Picker(String(localized: "Complete segment", table: "Export"), selection: Binding(
                        get: { model.selectedSegmentID ?? "" }, set: { model.select($0) })) {
                        ForEach(Array(model.segments.enumerated()), id: \.element.id) { index, segment in
                            Text(String(localized: "Segment \(JovraFormat.count(index + 1))", table: "Export")).tag(segment.id)
                        }
                    }
                } label: {
                    Text(String(localized: "Complete segment · \(JovraFormat.count((model.segments.firstIndex { $0.id == model.selectedSegmentID } ?? 0) + 1))", table: "Export"))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }.buttonStyle(.jovraSecondary)
                Button(String(localized: "Use whole segment", table: "Export")) {
                    if let id = model.selectedSegmentID { model.select(id) }
                }.buttonStyle(.jovraSecondary)
            }
            field(String(localized: "Start time (ms)", table: "Export"), text: $model.fromText, id: "export.from")
            field(String(localized: "End time (ms)", table: "Export"), text: $model.toText, id: "export.to")
            Toggle(isOn: $model.includeAudio) {
                Label(String(localized: "Include audio", table: "Export"), systemImage: model.includeAudio ? "checkmark.circle.fill" : "circle")
                    .frame(maxWidth: .infinity, minHeight: 52)
            }.toggleStyle(.button).buttonStyle(.jovraSecondary).accessibilityIdentifier("export.audio")
            Text("Range values use the session clock in milliseconds. Gaps cannot be exported.", tableName: "Export")
                .font(.jovraLabel).fixedSize(horizontal: false, vertical: true)
        }.disabled(model.isWorking).jovraCard(padding: Space.x2)
    }

    private func field(_ title: String, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text(title).fixedSize(horizontal: false, vertical: true)
            JovraTextInput(text: text, title: title, identifier: id, keyboardType: .numbersAndPunctuation)
                .padding(.horizontal, Space.x2).frame(minHeight: 64)
                .background(Color.jovra(.surfaceSunken), in: RoundedRectangle(cornerRadius: Radius.control))
        }
    }

    private func done(_ package: JovraMedia.LocalExportPackage) -> some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text("Saved on this iPhone", tableName: "Export").font(.jovraHeadline).accessibilityIdentifier("export.done")
            Text(String(localized: "Match-data version \(JovraFormat.count(package.eventLogVersion)) · \(JovraFormat.count(package.videoFrames)) decoded frames", table: "Export"))
                .fixedSize(horizontal: false, vertical: true)
            Text(package.includesAudio ? String(localized: "Audio included", table: "Export") : String(localized: "No audio included", table: "Export"))
            if model.isStale == true { Text("Exported before a correction", tableName: "Export") }
            else if model.isStale == nil { Text("Latest correction status is unavailable.", tableName: "Export") }
            Text(verbatim: "clip.mp4 · session.json · points.csv · stats.csv").font(.jovraLabel)
                .fixedSize(horizontal: false, vertical: true)
            ShareLink(items: [package.clip, package.sessionJSON, package.pointsCSV, package.statsCSV]) {
                Label(String(localized: "Share four files", table: "Export"), systemImage: "square.and.arrow.up")
            }.buttonStyle(.jovraPrimary).accessibilityIdentifier("export.share")
        }.jovraCard(padding: Space.x2)
    }
}
