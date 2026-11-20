import Foundation
import JovraCore
import JovraMedia

/// The compact pre-flight strip (N8 on S04): storage, battery and heat, each pass, warn or fail with a
/// symbol and words. Nothing here blocks recording (only camera access can, on S05).
struct PreflightCheck: Equatable, Identifiable {
    enum Kind: String { case storage, battery, heat }
    enum Tone: Equatable { case pass, warn, fail, unknown }

    var kind: Kind
    var tone: Tone
    /// The chip's words ("Storage ready", "Battery 78%", "Phone cool").
    var text: String
    /// The fuller sentence VoiceOver reads after the check's name.
    var detail: String

    var id: Kind { kind }

    var symbol: String {
        switch tone {
        case .pass: "checkmark.circle.fill"
        case .warn: "exclamationmark.circle.fill"
        case .fail: "xmark.octagon.fill"
        case .unknown: "questionmark.circle"
        }
    }

    static func checks(budget: DeviceBudgetSnapshot?, estimate: StorageEstimate?) -> [PreflightCheck] {
        [storage(estimate), battery(budget), heat(budget)]
    }

    static func storage(_ estimate: StorageEstimate?) -> PreflightCheck {
        guard let estimate else {
            return .init(kind: .storage, tone: .unknown, text: String(localized: "Checking storage", table: "Record", comment: "Pre-flight chip"),
                         detail: String(localized: "Free space is being checked.", table: "Record", comment: "Pre-flight detail"))
        }
        let fits = JovraFormat.duration(seconds: Double(estimate.fitsSeconds))
        switch estimate.verdict {
        case .ready:
            return .init(kind: .storage, tone: .pass, text: String(localized: "Storage ready", table: "Record", comment: "Pre-flight chip"),
                         detail: String(localized: "Room for about \(fits).", table: "Record", comment: "Pre-flight detail"))
        case .lessThanPlanned:
            return .init(kind: .storage, tone: .warn, text: String(localized: "Room for about \(fits)", table: "Record", comment: "Pre-flight chip"),
                         detail: String(localized: "Less room than the planned length. Recording still starts.", table: "Record", comment: "Pre-flight detail"))
        case .almostFull:
            return .init(kind: .storage, tone: .fail, text: String(localized: "Less than 5 min of space", table: "Record", comment: "Pre-flight chip"),
                         detail: String(localized: "Free up space before you record.", table: "Record", comment: "Pre-flight detail"))
        }
    }

    static func battery(_ budget: DeviceBudgetSnapshot?) -> PreflightCheck {
        guard let budget, let fraction = budget.batteryFraction else {
            return .init(kind: .battery, tone: .unknown, text: String(localized: "Battery not reported", table: "Record", comment: "Pre-flight chip"),
                         detail: String(localized: "This device does not report a battery level.", table: "Record", comment: "Pre-flight detail"))
        }
        let percent = JovraFormat.percent(Int((fraction * 100).rounded(.down)))
        if budget.lowPowerMode {
            return .init(kind: .battery, tone: .warn, text: String(localized: "Low Power Mode on", table: "Record", comment: "Pre-flight chip"),
                         detail: String(localized: "Battery \(percent). Low Power Mode can lower the frame rate.", table: "Record", comment: "Pre-flight detail"))
        }
        if fraction < 0.3 {
            return .init(kind: .battery, tone: .warn, text: String(localized: "Battery \(percent)", table: "Record", comment: "Pre-flight chip"),
                         detail: String(localized: "Low battery. Plug in for a long session.", table: "Record", comment: "Pre-flight detail"))
        }
        return .init(kind: .battery, tone: .pass, text: String(localized: "Battery \(percent)", table: "Record", comment: "Pre-flight chip"),
                     detail: String(localized: "Enough charge to start.", table: "Record", comment: "Pre-flight detail"))
    }

    static func heat(_ budget: DeviceBudgetSnapshot?) -> PreflightCheck {
        switch budget?.thermalState {
        case nil:
            return .init(kind: .heat, tone: .unknown, text: String(localized: "Checking heat", table: "Record", comment: "Pre-flight chip"),
                         detail: String(localized: "The phone's temperature is being checked.", table: "Record", comment: "Pre-flight detail"))
        case .nominal, .fair:
            return .init(kind: .heat, tone: .pass, text: String(localized: "Phone cool", table: "Record", comment: "Pre-flight chip"),
                         detail: String(localized: "No heat limits.", table: "Record", comment: "Pre-flight detail"))
        case .serious, .critical, .shutdown:
            return .init(kind: .heat, tone: .warn, text: String(localized: "Phone warm · preview may turn off", table: "Record", comment: "Pre-flight chip"),
                         detail: String(localized: "Keep the phone in the shade. Recording continues.", table: "Record", comment: "Pre-flight detail"))
        }
    }

    var kindTitle: String {
        switch kind {
        case .storage: String(localized: "Storage", table: "Record", comment: "Pre-flight check name")
        case .battery: String(localized: "Battery", table: "Record", comment: "Pre-flight check name")
        case .heat: String(localized: "Heat", table: "Record", comment: "Pre-flight check name")
        }
    }

    var toneTitle: String {
        switch tone {
        case .pass: String(localized: "passed", table: "Record", comment: "Pre-flight result, spoken")
        case .warn: String(localized: "warning", table: "Record", comment: "Pre-flight result, spoken")
        case .fail: String(localized: "failed", table: "Record", comment: "Pre-flight result, spoken")
        case .unknown: String(localized: "not checked", table: "Record", comment: "Pre-flight result, spoken")
        }
    }
}
