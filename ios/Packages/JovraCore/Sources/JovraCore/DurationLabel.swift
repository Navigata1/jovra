/// Compact labels for elapsed time on court, as shown on stat tiles and session rows
/// ("54 min", "6h 42m"). Seconds are truncated, never rounded up, so a total is never overstated.
public enum DurationLabel {
    public static func compact(seconds: Double) -> String {
        let total = seconds.isFinite && seconds > 0 ? Int(seconds) : 0
        let minutes = total / 60
        guard minutes >= 60 else { return "\(minutes) min" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
