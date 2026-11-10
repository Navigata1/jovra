import JovraBenchmark
import SwiftUI

/// The whole recording on one line: held-out windows, rallies, hits (near above, far below), bounces,
/// hit candidates and the playhead. Click or drag to move.
struct TimelineStrip: View {
    @Environment(\.colorScheme) private var scheme
    let session: LabelSession

    var body: some View {
        let palette = Palette(scheme)
        let document = session.document
        let now = session.displayedTime.seconds
        let total = max(document?.labels.recording.duration.seconds ?? 0, 0.001)
        GeometryReader { proxy in
            Canvas { context, size in
                func x(_ seconds: Double) -> CGFloat { CGFloat(seconds / total) * size.width }
                let mid = size.height / 2
                context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6), with: .color(palette.raised))
                guard let document else { return }
                let split = document.labels.split
                for index in split.heldOutWindows {
                    let range = split.range(ofWindow: index)
                    let from = Double(range.start.numerator) / Double(range.start.denominator)
                    let to = Double(range.end.numerator) / Double(range.end.denominator)
                    let band = CGRect(x: x(from), y: 0, width: max(x(to) - x(from), 1), height: size.height)
                    context.fill(Path(band), with: .color(palette.heldOut.opacity(0.22)))
                    // Hatched as well as tinted: held-out windows do not rely on colour.
                    var hatch = Path()
                    var offset = band.minX
                    while offset < band.maxX {
                        hatch.move(to: CGPoint(x: offset, y: size.height)); hatch.addLine(to: CGPoint(x: min(offset + 6, band.maxX), y: size.height - 6))
                        offset += 8
                    }
                    context.stroke(hatch, with: .color(palette.heldOut), lineWidth: 1)
                }
                for rally in document.labels.rallies {
                    let end = rally.end?.seconds ?? rally.start.seconds
                    context.fill(Path(CGRect(x: x(rally.start.seconds), y: mid - 2, width: max(x(end) - x(rally.start.seconds), 2), height: 4)),
                                 with: .color(palette.text.opacity(0.55)))
                }
                if let open = document.openRallyStart {
                    context.fill(Path(CGRect(x: x(open.seconds), y: mid - 2, width: max(x(now) - x(open.seconds), 2), height: 4)),
                                 with: .color(palette.warning))
                }
                for candidate in document.labels.hitCandidates?.items ?? [] where candidate.decision == .pending {
                    let dot = CGRect(x: x(candidate.time.seconds) - 1.5, y: size.height - 7, width: 3, height: 3)
                    context.fill(Path(ellipseIn: dot), with: .color(palette.secondary))
                }
                for hit in document.labels.hits {
                    let near = hit.player == .near
                    let tick = CGRect(x: x(hit.time.seconds) - 1, y: near ? 5 : mid + 3, width: 2, height: mid - 8)
                    context.fill(Path(tick), with: .color(palette.accent))
                }
                for bounce in document.labels.bounces {
                    let dot = CGRect(x: x(bounce.time.seconds) - 2.5, y: mid - 2.5, width: 5, height: 5)
                    context.stroke(Path(ellipseIn: dot), with: .color(palette.text), lineWidth: 1.2)
                }
                context.fill(Path(CGRect(x: x(now) - 1, y: 0, width: 2, height: size.height)), with: .color(palette.text))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let fraction = min(max(value.location.x / max(proxy.size.width, 1), 0), 1)
                session.seek(to: RationalTime(value: Int64((Double(fraction) * total * 1000).rounded()), timescale: 1000))
            })
        }
        .frame(height: 44)
        // To assistive technologies the strip is what it behaves like: a slider over the recording.
        .accessibilityRepresentation {
            Slider(value: Binding(get: { min(max(now, 0), total) },
                                  set: { session.seek(to: RationalTime(value: Int64(($0 * 1000).rounded()), timescale: 1000)) }),
                   in: 0...total) { Text("Timeline") }
                .accessibilityValue("\(session.displayedTime.clock) of \(document?.labels.recording.duration.clock ?? "0:00.000")")
                .accessibilityIdentifier("timeline")
        }
    }
}
