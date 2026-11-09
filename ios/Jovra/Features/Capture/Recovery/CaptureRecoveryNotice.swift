import SwiftUI

struct CaptureRecoveryNotice: View {
    let summary: StartupRecoverySummary

    var body: some View {
        if summary.recovered > 0 {
            StateCard(symbol: "checkmark.circle",
                      title: String(localized: "Recording recovered", table: "Capture.Recovery"),
                      message: String(localized: "Verified recordings are ready in your library.", table: "Capture.Recovery"))
        }
        if summary.partiallyRecovered > 0 {
            StateCard(symbol: "exclamationmark.triangle",
                      title: String(localized: "Recording partially recovered", table: "Capture.Recovery"),
                      message: String(localized: "Playable video is ready in your library. Some footage could not be recovered.", table: "Capture.Recovery"))
        }
        if summary.refused > 0 || summary.scanFailed {
            StateCard(symbol: "exclamationmark.triangle",
                      title: String(localized: "Recovery needs attention", table: "Capture.Recovery"),
                      message: String(localized: "JOVRA could not finish checking every recording. It did not delete any original video.", table: "Capture.Recovery"))
        }
    }
}
