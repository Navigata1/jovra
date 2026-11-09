import JovraCore
import JovraMedia
import SwiftUI

/// Frame-exact readout text: "f 46,000 · 12:46.67 · 60 fps", with " · 0.5×" when the rate is not 1×.
enum ReadoutFormat {
    /// Minutes and seconds with hundredths ("12:46.67"), hours when needed ("1:02:03.50").
    static func time(seconds: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let hundredths = Int((max(0, seconds) * 100).rounded())
        let whole = hundredths / 100, fraction = hundredths % 100
        let hours = whole / 3600, minutes = (whole % 3600) / 60, secs = whole % 60
        let decimal = locale.decimalSeparator ?? "."
        let head = hours > 0 ? "\(hours):" + twoDigits(minutes) : "\(minutes)"
        return head + ":" + twoDigits(secs) + decimal + twoDigits(fraction)
    }

    static func fps(_ rate: FrameRate, locale: Locale = .autoupdatingCurrent) -> String {
        if rate.perSeconds == 1 { return JovraFormat.count(rate.frames, locale: locale) }
        return rate.framesPerSecond.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }

    static func rate(_ rate: PlaybackRate, locale: Locale = .autoupdatingCurrent) -> String {
        Double(rate.value).formatted(.number.precision(.fractionLength(0...2)).locale(locale)) + "×"
    }

    private static func twoDigits(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
}

/// The trailing readout of the jog strip. Tapping it switches between frames and time only.
struct FrameReadout: View {
    var readout: PlaybackReadout
    @State private var showsFrames = true

    var body: some View {
        Button { showsFrames.toggle() } label: {
            Text(text)
                .font(.jovraTimecode)
                .foregroundStyle(.jovra(.textPrimary))
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: HitTarget.minimum)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Position", tableName: "DesignSystem.Video"))
        .accessibilityValue(Text(text))
        .accessibilityHint(showsFrames ? Text("Shows time only", tableName: "DesignSystem.Video")
                                       : Text("Shows the frame number", tableName: "DesignSystem.Video"))
        .accessibilityIdentifier("playback.readout")
    }

    var text: String { Self.text(for: readout, showsFrames: showsFrames) }

    static func text(for readout: PlaybackReadout, showsFrames: Bool = true) -> String {
        let time = ReadoutFormat.time(seconds: readout.seconds)
        let fps = ReadoutFormat.fps(readout.frameRate)
        let base = showsFrames
            ? String(localized: "f \(JovraFormat.count(readout.frame)) · \(time) · \(fps) fps", table: "DesignSystem.Video",
                     comment: "Frame readout: frame number, time, frames per second, e.g. “f 46,000 · 12:46.67 · 60 fps”")
            : String(localized: "\(time) · \(fps) fps", table: "DesignSystem.Video", comment: "Frame readout without the frame number")
        guard readout.rate != .normal else { return base }
        return String(localized: "\(base) · \(ReadoutFormat.rate(readout.rate))", table: "DesignSystem.Video",
                      comment: "Frame readout followed by the playback rate, e.g. “… · 0.5×”")
    }
}
