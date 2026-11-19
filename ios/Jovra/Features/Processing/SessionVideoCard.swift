import JovraCore
import SwiftUI

/// The "selected video" card of screen 7: the poster frame (or court art when there is none) with the
/// length, then the title, length and resolution, date, and the Sample label for sample sessions.
struct SessionVideoCard: View {
    var title: String
    var meta: String
    var date: String
    var isSample: Bool
    var length: String?
    var thumbnail: CGImage?
    var viewable: Bool
    var onOpen: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.x2))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Space.x2))
        layout {
            poster
            VStack(alignment: .leading, spacing: Space.half) {
                Text(title)
                    .font(.jovraHeadline)
                    .foregroundStyle(.jovra(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("processing.video.title")
                Text(meta).font(.jovraLabel).foregroundStyle(.jovra(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                Text(date).font(.jovraCaption).foregroundStyle(.jovra(.textSecondary)).padding(.top, Space.half)
                if isSample { SampleBadge(size: .small).accessibilityIdentifier("processing.sample") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .jovraCard(padding: Space.x1 + Space.half)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("processing.video")
    }

    /// A play button once the video can be watched; until then (and in the demo) a still picture, so
    /// nothing looks tappable that is not.
    @ViewBuilder private var poster: some View {
        if viewable {
            Button(action: onOpen) { posterArt(showsPlay: true) }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Play \(title)", tableName: "Processing"))
                .accessibilityIdentifier("processing.video.play")
        } else {
            posterArt(showsPlay: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Video length \(length ?? "")", tableName: "Processing"))
        }
    }

    /// The picture never sets the poster's size: a 16:10 base takes the width offered and the frame is
    /// drawn over it, so a large source image cannot push the card wider than the screen.
    private func posterArt(showsPlay: Bool) -> some View {
        Color.jovra(.courtSurface)
            .aspectRatio(16 / 10, contentMode: .fit)
            .overlay {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1).resizable().scaledToFill()
                } else {
                    CourtLinesBackdrop().stroke(Color.jovra(.courtLine), lineWidth: 1.5)
                }
            }
            .overlay {
                // A scrim under the controls keeps the white play glyph and length legible on any frame.
                LinearGradient(colors: [.black.opacity(0), .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: Space.x1) {
                    if showsPlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 32, height: 32)
                            .background(.black.opacity(0.45), in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5))
                    }
                    if let length {
                        Text(verbatim: length).font(.footnote.weight(.semibold).monospacedDigit())
                            .lineLimit(1)
                            .padding(.horizontal, Space.x1).padding(.vertical, 2)
                            .background(.black.opacity(0.6), in: Capsule())
                    }
                }
                .foregroundStyle(.white)
                .padding(Space.x1)
            }
            .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 190)
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}

extension SessionVideoCard {
    init(document: SessionDocument, thumbnail: CGImage?, viewable: Bool, onOpen: @escaping () -> Void) {
        let segments = document.recording.segments.filter(\.finalized)
        let milliseconds = document.recording.durationMs ?? segments.reduce(0) { $0 + $1.durationMs }
        let seconds = Double(milliseconds) / 1000
        var parts = [seconds >= 60 ? JovraFormat.duration(seconds: seconds) : JovraFormat.clock(seconds: seconds)]
        if let first = segments.first { parts.append("\(JovraFormat.count(min(first.width, first.height)))p") }
        let created = (try? Date(document.createdAt, strategy: .iso8601)).map { JovraFormat.date($0) } ?? ""
        self.init(title: document.title, meta: parts.joined(separator: " · "), date: created,
                  isSample: document.sample != nil, length: JovraFormat.clock(seconds: seconds),
                  thumbnail: thumbnail, viewable: viewable, onOpen: onOpen)
    }
}
