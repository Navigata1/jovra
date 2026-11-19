import JovraBenchmark
import SwiftUI

/// The labelling window: header, picture, transport and timeline, sidebar, and one line that says what the
/// last key did.
public struct LabelToolView: View {
    @Environment(\.colorScheme) private var scheme
    let session: LabelSession

    public init(session: LabelSession) {
        self.session = session
    }

    public var body: some View {
        let palette = Palette(scheme)
        VStack(spacing: 0) {
            header(palette)
            Rectangle().fill(palette.line).frame(height: 1)
            HStack(spacing: 0) {
                main(palette)
                Sidebar(session: session)
            }
            Rectangle().fill(palette.line).frame(height: 1)
            statusBar(palette)
        }
        .background(palette.background)
        .foregroundStyle(palette.text)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Labelling workspace")
    }

    // MARK: Header

    private func header(_ palette: Palette) -> some View {
        HStack(spacing: 10) {
            Text("JOVRA Label")
                .font(.title3.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            if let recording = session.labels?.recording {
                Chip(text: "rec-\(recording.sha256.prefix(12))", systemImage: "number")
                    .accessibilityLabel("Recording \(recording.sha256.prefix(12))")
                Chip(text: "\(recording.width)×\(recording.height)")
                Chip(text: Self.rateText(recording) + (recording.variableFrameRate ? " · variable" : ""))
                if let split = session.labels?.split {
                    Chip(text: "\(split.heldOutWindows.count) of \(split.windowCount) windows held out", systemImage: "lock")
                        .help("The held-out windows are fixed by the recording's hash. Label them like any other part.")
                }
            }
            Spacer(minLength: 8)
            if session.isReady {
                Chip(text: saveText, systemImage: session.isDirty ? "circle.fill" : "checkmark", emphasised: session.isDirty)
                    .accessibilityIdentifier("save-state")
            }
            Button("Open…") { session.perform(.open) }
                .help("⌘O")
                .accessibilityIdentifier("open-button")
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 10)
        .background(palette.panel)
    }

    private var saveText: String {
        if session.isDirty { return "Unsaved changes" }
        guard let saved = session.lastSaved else { return "No changes" }
        return "Saved " + saved.formatted(date: .omitted, time: .shortened)
    }

    static func rateText(_ recording: BenchmarkLabels.Recording) -> String {
        let rate = Double(recording.frameRate.num) / Double(recording.frameRate.den)
        return (rate == rate.rounded() ? String(format: "%.0f", rate) : String(format: "%.2f", rate)) + " fps"
    }

    // MARK: Main column

    @ViewBuilder private func main(_ palette: Palette) -> some View {
        switch session.phase {
        case .empty:
            message(palette, symbol: "film", title: "Open a recording to label",
                    body: "Choose a video file on this Mac (⌘O). Labels are times and points only: the video is read here and never copied, uploaded or sent anywhere.",
                    button: true)
        case .opening(let step):
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text(step).font(.title3).multilineTextAlignment(.center)
                Text("A long recording takes a few seconds.").foregroundStyle(palette.secondary)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("opening")
        case .failed(let reason):
            message(palette, symbol: "exclamationmark.triangle", title: "This recording could not be opened", body: reason, button: true)
        case .ready:
            VStack(spacing: 12) {
                VideoCanvas(session: session)
                transport(palette)
                VStack(alignment: .leading, spacing: 6) {
                    TimelineStrip(session: session)
                    Text("Hits are bars (near player above the line, far player below), bounces rings, rallies the thick line, hit candidates dots. Hatched windows are held out.")
                        .font(.caption)
                        .foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Metrics.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func message(_ palette: Palette, symbol: String, title: String, body: String, button: Bool) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 44, weight: .light)).foregroundStyle(palette.secondary).accessibilityHidden(true)
            Text(title).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            Text(body).foregroundStyle(palette.secondary).multilineTextAlignment(.center).frame(maxWidth: 460)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("message-body")
            if button {
                Button("Open a recording…") { session.perform(.open) }
                    .buttonStyle(ProminentButtonStyle())
                    .padding(.top, 4)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func transport(_ palette: Palette) -> some View {
        HStack(spacing: 14) {
            Button {
                session.perform(.playPause)
            } label: {
                Image(systemName: session.isPlaying ? "pause.fill" : "play.fill").frame(width: 20, height: 20)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(session.isPlaying ? "Pause" : "Play")
            .help("Space")
            VStack(alignment: .leading, spacing: 1) {
                Text(session.displayedTime.clock)
                    .font(.system(.title2, design: .monospaced).weight(.semibold))
                    .accessibilityLabel("Time \(session.displayedTime.clock)")
                    .accessibilityIdentifier("time")
                Text(frameText).font(.caption).foregroundStyle(palette.secondary)
            }
            Spacer(minLength: 8)
            if let total = session.labels?.recording.duration {
                Text("of \(total.clock)").font(.callout.monospacedDigit()).foregroundStyle(palette.secondary)
            }
            Chip(text: LabelSession.rateText(session.rate), systemImage: "speedometer")
                .accessibilityLabel("Playback speed \(LabelSession.rateText(session.rate))")
        }
    }

    private var frameText: String {
        guard let recording = session.labels?.recording else { return "" }
        let frame = Int((session.displayedTime.seconds * Double(recording.frameRate.num) / Double(recording.frameRate.den)).rounded())
        return recording.variableFrameRate ? "about frame \(frame) (variable frame rate)" : "frame \(frame)"
    }

    // MARK: Status

    private func statusBar(_ palette: Palette) -> some View {
        HStack(spacing: 8) {
            if let notice = session.notice {
                Image(systemName: symbol(notice.kind)).foregroundStyle(colour(notice.kind, palette)).accessibilityHidden(true)
                Text(notice.text)
                    .foregroundStyle(notice.kind == .info ? palette.text : colour(notice.kind, palette))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("status")
            } else {
                Text("Ready.").foregroundStyle(palette.secondary).accessibilityIdentifier("status")
            }
            Spacer(minLength: 8)
            if let url = session.labelsURL {
                Text(url.lastPathComponent).font(.callout.monospaced()).foregroundStyle(palette.secondary).lineLimit(1).truncationMode(.middle)
                    .help(url.path)
                    .accessibilityLabel("Label file \(url.lastPathComponent)")
            }
        }
        .font(.callout)
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.panel)
    }

    private func symbol(_ kind: LabelSession.Notice.Kind) -> String {
        switch kind {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        }
    }

    private func colour(_ kind: LabelSession.Notice.Kind, _ palette: Palette) -> Color {
        switch kind {
        case .info: palette.secondary
        case .warning: palette.warning
        case .error: palette.danger
        }
    }
}
