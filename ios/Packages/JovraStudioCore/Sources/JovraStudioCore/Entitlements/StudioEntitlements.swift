import Foundation

/// What this build of JOVRA allows in Studio (spec SD2, working default D-4, open question 9).
///
/// On-device Studio is free and `localStudio` is **true in every build configuration**: Debug and Release read the
/// same literal, and no `DEBUG` condition touches it. It exists so a later pricing decision (Jon's answer to open
/// question 9, a pricing ADR) is a configuration change rather than a redesign: every local Studio entry and film
/// path reads it. Whatever it says, originals, exports, local films already made and core v1 are never locked
/// (ADR-0013): turning it off only refuses to start new Studio film projects and new film locks.
///
/// The only way to build it `false` is an explicit scratch build with the compilation condition
/// `JOVRA_STUDIO_LOCAL_OFF` (`swift test -Xswiftc -DJOVRA_STUDIO_LOCAL_OFF`), which exists to prove the refusal path.
public struct StudioEntitlements: Equatable, Sendable {
    /// On-device Studio: multi-phone capture, imported angles, on-device sync, lessons and the template films.
    public let localStudio: Bool

    public init(localStudio: Bool) {
        self.localStudio = localStudio
    }

    /// The value this build was compiled with.
    public static let build = StudioEntitlements(localStudio: buildLocalStudio)

    /// Shown when a Studio film path is refused because `localStudio` is off. It says what still works.
    public static let localStudioUnavailableReason =
        "Studio films aren't available in this version of JOVRA. Your recordings, exports and films you already made stay available."

    private static var buildLocalStudio: Bool {
        #if JOVRA_STUDIO_LOCAL_OFF
        return false
        #else
        return true
        #endif
    }
}
