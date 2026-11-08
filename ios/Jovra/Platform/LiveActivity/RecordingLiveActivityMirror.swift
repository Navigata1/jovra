import ActivityKit
import Foundation
import JovraCore
import JovraMedia
import os
import UIKit

/// T60 SPIKE (throwaway branch). Mirrors capture heartbeats into a Live Activity. It never blocks recording:
/// every ActivityKit call is fire-and-forget on a serial task chain, and every failure is only logged.
@MainActor
final class RecordingLiveActivityMirror {
    private static let log = Logger(subsystem: "com.islanddevcrew.jovra", category: "T60Spike")
    private var policy = RecordingLiveActivityPolicy()
    private var activityID: String?
    private var chain: Task<Void, Never>?
    private var sequence = 0
    private let isSample: Bool
    private var lastStatusLog = Date.distantPast
    private var observers: [NSObjectProtocol] = []

    init(isSample: Bool) {
        self.isSample = isSample
        // Spike instrumentation: app lifecycle transitions, to tell "inactive" (Notification Centre over the
        // app; recording should continue) from "background" (CaptureScreen pauses).
        let names: [Notification.Name] = [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification,
                                          UIApplication.willEnterForegroundNotification, UIApplication.didBecomeActiveNotification]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                Self.log.notice("T60 lifecycle \(name.rawValue, privacy: .public)")
            }
        }
    }

    func observe(_ status: CaptureStatus, now: Date = Date()) {
        let heartbeat = RecordingHeartbeat(phase: status.phase, recordingSeconds: status.recordingTime.map(Self.seconds),
                                           savedThroughSeconds: status.savedThrough.map(Self.seconds),
                                           batteryFraction: status.budget?.batteryFraction)
        if now.timeIntervalSince(lastStatusLog) >= 1 {
            lastStatusLog = now
            let appState = UIApplication.shared.applicationState.rawValue
            Self.log.notice("T60 status phase=\(status.phase.rawValue, privacy: .public) rec=\(heartbeat.recordingSeconds ?? -1, privacy: .public) saved=\(heartbeat.savedThroughSeconds ?? -1, privacy: .public) appState=\(appState, privacy: .public)")
        }
        guard let update = policy.update(for: heartbeat, at: now) else { return }
        sequence += 1
        let number = sequence
        let content = ActivityContent(state: update.state, staleDate: update.staleDate)
        let attributes = RecordingActivityAttributes(isSample: isSample)
        let previous = chain
        chain = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            await self.apply(content, attributes: attributes, number: number, sentAt: now)
        }
    }

    private func apply(_ content: ActivityContent<RecordingActivityAttributes.ContentState>,
                       attributes: RecordingActivityAttributes, number: Int, sentAt: Date) async {
        let phase = content.state.phase.rawValue
        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        if let activityID {
            let state = await Self.push(content, to: activityID)
            Self.log.notice("T60 update #\(number, privacy: .public) phase=\(phase, privacy: .public) rec=\(content.state.recordingSeconds, privacy: .public) sent=\(sentAt.timeIntervalSince1970, privacy: .public) state=\(state, privacy: .public)")
            return
        }
        guard content.state.phase != .saved else { return }
        // An activity left by a previous process (crash, jetsam, kill) is ended before a new one starts.
        let ended = await Self.endLeftovers()
        if ended > 0 { Self.log.notice("T60 ended \(ended, privacy: .public) leftover activities") }
        do {
            activityID = try Activity.request(attributes: attributes, content: content, pushType: nil).id
            Self.log.notice("T60 request #\(number, privacy: .public) enabled=\(enabled, privacy: .public) id=\(self.activityID ?? "-", privacy: .public) sent=\(sentAt.timeIntervalSince1970, privacy: .public)")
        } catch {
            Self.log.error("T60 request failed enabled=\(enabled, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// Looks the activity up by id off the main actor (Activity is not Sendable under Swift 6).
    nonisolated private static func push(_ content: ActivityContent<RecordingActivityAttributes.ContentState>,
                                         to id: String) async -> String {
        guard let activity = Activity<RecordingActivityAttributes>.activities.first(where: { $0.id == id }) else { return "missing" }
        if content.state.phase == .saved { await activity.end(content, dismissalPolicy: .default) }
        else { await activity.update(content) }
        return String(describing: activity.activityState)
    }

    nonisolated private static func endLeftovers() async -> Int {
        let leftovers = Activity<RecordingActivityAttributes>.activities
        for leftover in leftovers { await leftover.end(nil, dismissalPolicy: .immediate) }
        return leftovers.count
    }

    private static func seconds(_ time: JovraCore.MediaTime) -> Double { Double(time.value) / Double(time.timescale) }
}
