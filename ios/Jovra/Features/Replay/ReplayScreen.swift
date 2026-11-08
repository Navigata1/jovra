import AVKit
import JovraCore
import SwiftUI

/// Original playback and bounded manual decisions. Full T28 timeline/filter tools remain separate.
struct ReplayScreen: View {
    nonisolated static let isPlaceholder = false
    var request: ReplayRequest
    @Environment(AppRouter.self) private var router
    @Environment(\.localCaptureLibrary) private var library
    @State private var playback = ReplayPlaybackModel()
    @State private var review = ReviewedPointModel()
    @State private var startText = JovraFormat.count(0)
    @State private var endText = JovraFormat.count(500)
    @State private var formError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CloseControl(label: String(localized: "Close replay", table: "Replay"), identifier: "replay.close") {
                    playback.close(); router.dismissFullScreen()
                }
                Spacer()
                JovraLockup(height: 28)
            }.padding(Space.x2)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x2) {
                    Text(AppDestination.fullScreen(.replay(request)).info.title)
                        .jovraDisplayTitle().accessibilityAddTraits(.isHeader).accessibilityIdentifier("screen.title")
                    if let document = playback.document {
                        Text(document.title).font(.jovraHeadline).fixedSize(horizontal: false, vertical: true)
                        if document.sample != nil { SampleBadge().accessibilityIdentifier("replay.sample") }
                    }
                    if case .unavailable = library {
                        Text("Local library unavailable. Reopen JOVRA to try again.", tableName: "Replay")
                    } else {
                        video
                        if let error = playback.error { Text(error).accessibilityIdentifier("replay.error") }
                        if review.document != nil { decisions }
                        if let error = review.error { Text(error).accessibilityIdentifier("review.error") }
                    }
                }
                .font(.jovraBody).foregroundStyle(.jovra(.textPrimary))
                .padding(.horizontal, Space.screenMargin).padding(.bottom, Space.x4)
                .frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
            }.clipped().scrollDismissesKeyboard(.interactively).accessibilityIdentifier("replay.scroll")
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .background(Color.jovra(.background).ignoresSafeArea()).preferredColorScheme(.dark)
        .task(id: request) {
            guard case .ready(let library) = library else { return }
            await playback.open(library: library, session: request.session)
            await review.open(library: library, session: request.session)
            if let id = request.point { review.select(id.rawValue) }
        }
        .onDisappear { playback.close() }
    }

    @ViewBuilder private var video: some View {
        if let player = playback.player {
            ZStack {
                VideoPlayer(player: player)
                if playback.showStill, let frame = playback.frame {
                    Image(decorative: frame.image, scale: 1).resizable().scaledToFit().accessibilityHidden(true)
                }
            }.aspectRatio(16 / 9, contentMode: .fit).frame(minHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            if playback.segments.count > 1 {
                Picker(String(localized: "Recording segment", table: "Replay"), selection: Binding(
                    get: { playback.selectedSegmentID ?? "" },
                    set: { id in Task { await playback.selectSegment(id) } })) {
                    ForEach(Array(playback.segments.enumerated()), id: \.element.id) { offset, segment in
                        Text("Segment \(JovraFormat.count(offset + 1))", tableName: "Replay").tag(segment.id)
                    }
                }.pickerStyle(.menu).frame(minHeight: 52).disabled(playback.isWorking)
                Text("Segments play separately; recording gaps are preserved.", tableName: "Replay")
                    .font(.jovraLabel).fixedSize(horizontal: false, vertical: true)
            }
            Text(playback.frameStatus).font(.jovraLabel).fixedSize(horizontal: false, vertical: true)
            if let frame = playback.frame {
                Text("Selected decoded frame", tableName: "Replay").font(.jovraLabel)
                Text("f \(JovraFormat.count(frame.index)) · \(JovraFormat.clock(seconds: frame.time.seconds))", tableName: "Replay")
                    .monospacedDigit().accessibilityIdentifier("replay.frame")
            }
            ViewThatFits(in: .horizontal) {
                HStack { transport }
                VStack { transport }
            }
            .disabled(playback.isWorking)
        } else if playback.isWorking {
            ProgressView(String(localized: "Opening the original…", table: "Replay"))
        }
    }

    @ViewBuilder private var transport: some View {
        Button(String(localized: "Previous frame", table: "Replay")) { Task { await playback.step(-1) } }
            .buttonStyle(.jovraSecondary).disabled(playback.frame == nil).accessibilityIdentifier("replay.frame.previous")
        Button(String(localized: "Play", table: "Replay")) { playback.play() }
            .buttonStyle(.jovraAccent).accessibilityIdentifier("replay.play")
        Button(String(localized: "Pause", table: "Replay")) { playback.pause() }
            .buttonStyle(.jovraSecondary).accessibilityIdentifier("replay.pause")
        Button(String(localized: "Next frame", table: "Replay")) { Task { await playback.step(1) } }
            .buttonStyle(.jovraSecondary).disabled(playback.frame == nil).accessibilityIdentifier("replay.frame.next")
    }

    private var decisions: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text("Review the point", tableName: "Replay").font(.jovraHeadline).accessibilityAddTraits(.isHeader)
            Text("Enter the point's start and end in session milliseconds, then choose the winner. Other measurements stay unknown.", tableName: "Replay")
                .fixedSize(horizontal: false, vertical: true)
            field(String(localized: "Point start (ms)", table: "Replay"), text: $startText, id: "review.startMs")
            field(String(localized: "Point end (ms)", table: "Replay"), text: $endText, id: "review.endMs")
            forSides(prefix: "review.add", correct: false)
            if let formError { Text(formError).accessibilityIdentifier("review.rangeError") }
            ForEach(Array(review.points.enumerated()), id: \.element.id) { offset, point in
                let winner = point.winner.value?.rawValue == "A" ? name(.a) : (point.winner.value == nil ? "—" : name(.b))
                Button(String(localized: "Point \(JovraFormat.count(offset + 1)) · \(winner)", table: "Replay")) { review.select(point.id) }
                    .buttonStyle(.jovraSecondary).accessibilityIdentifier("review.point.\(offset + 1)")
                    .accessibilityValue(review.selectedID == point.id ? String(localized: "Selected", table: "Replay") : "")
            }
            if let selected = review.selected {
                Text("Score before selected point", tableName: "Replay").font(.jovraHeadline)
                Text(review.scoreBefore).font(.jovraMetric).accessibilityIdentifier("review.scoreBefore")
                if review.document?.sample != nil { SampleBadge().accessibilityIdentifier("review.score.sample") }
                let server = review.document?.players.first { $0.id == selected.server.value }?.displayName ?? "—"
                Text("Server: \(server) · Server's score first", tableName: "Replay").fixedSize(horizontal: false, vertical: true)
                ProvenanceBadge(kind: .provenance(selected.provenance))
                forSides(prefix: "review.correct", correct: true)
            }
            Text("Points won by \(name(.a)): \(review.pointsWonAFraction)", tableName: "Replay")
                .font(.jovraHeadline).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("review.pointsWon.A")
            if review.pointsWonA?.evidence.sample == true { SampleBadge().accessibilityIdentifier("review.pointsWon.sample") }
            if let provenance = review.pointsWonA?.evidence.provenance { ProvenanceBadge(kind: .provenance(provenance)) }
            stat(String(localized: "First serves in by \(name(.a))", table: "Replay"), value: review.firstServeInA, id: "review.firstServes.A")
            stat(String(localized: "Shots", table: "Replay"), value: review.shots, id: "review.shots")
            Button(String(localized: "Export clip and data", table: "Replay")) {
                playback.pause(); router.present(sheet: .clipExport(request.session, nil))
            }.buttonStyle(.jovraAccent).accessibilityIdentifier("replay.export")
        }
        .disabled(review.isWorking).jovraCard()
    }

    private func forSides(prefix: String, correct: Bool) -> some View {
        VStack(spacing: Space.x1) {
            ForEach([Side.a, .b], id: \.rawValue) { side in
                Button(correct ? String(localized: "Correct winner to \(name(side))", table: "Replay")
                       : String(localized: "Add point won by \(name(side))", table: "Replay")) {
                    formError = nil
                    if correct { Task { await review.correct(winner: side) } }
                    else if let start = milliseconds(startText), let end = milliseconds(endText) {
                        Task { await review.append(winner: side, startMs: start, endMs: end) }
                    } else { formError = String(localized: "Enter whole milliseconds inside your recording.", table: "Replay") }
                }.buttonStyle(.jovraSecondary).accessibilityIdentifier(prefix + "." + side.rawValue)
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text(title).font(.jovraLabel).fixedSize(horizontal: false, vertical: true)
            JovraTextInput(text: text, title: title, identifier: id, keyboardType: .numbersAndPunctuation)
                .padding(.horizontal, Space.x2).frame(minHeight: 64)
                .background(Color.jovra(.surfaceSunken), in: RoundedRectangle(cornerRadius: Radius.control))
        }
    }
    private func name(_ side: Side) -> String {
        let id = side == .a ? review.document?.sides?.A.first : review.document?.sides?.B.first
        return review.document?.players.first { $0.id == id }?.displayName
            ?? (side == .a ? String(localized: "Player A", table: "Replay") : String(localized: "Player B", table: "Replay"))
    }
    private func stat(_ title: String, value: DerivedStat?, id: String) -> some View {
        let number: String
        switch value?.value {
        case .count(let count): number = JovraFormat.count(count)
        case .ratio(let ratio): number = JovraFormat.count(ratio.n) + "/" + JovraFormat.count(ratio.d)
        case nil: number = "—"
        }
        return VStack(alignment: .leading, spacing: Space.x1) {
            Text("\(title): \(number)", tableName: "Replay").fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(id)
            if value?.evidence.sample == true { SampleBadge().accessibilityIdentifier(id + ".sample") }
            if let provenance = value?.evidence.provenance { ProvenanceBadge(kind: .provenance(provenance)) }
        }
    }
    private func milliseconds(_ text: String) -> Int? {
        let formatter = NumberFormatter(); formatter.locale = .autoupdatingCurrent
        let normalized = text.replacingOccurrences(of: formatter.groupingSeparator ?? ",", with: "")
        let digits = normalized.compactMap(\.wholeNumberValue)
        guard !digits.isEmpty, digits.count == normalized.count else { return nil }
        return Int(digits.map(String.init).joined())
    }
}
