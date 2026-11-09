import Foundation

/// What a block of the UI counts after the one sample-scope rule (GLOSSARY: Sample data).
public struct SampleScoped<Element> {
    /// The items the block counts.
    public let items: [Element]
    /// True only when every item in scope is Sample: the block carries the Sample badge.
    public let isSample: Bool
}

extension SampleScoped: Equatable where Element: Equatable {}
extension SampleScoped: Sendable where Element: Sendable {}

/// The single rule every screen cites (Home tiles, Progress, the practice plan, equipment hours): samples count
/// only when the whole scope is sample, and then the block is flagged Sample; any scope that mixes real and
/// sample items counts the real items only, so demo data never contaminates the player's own numbers.
public enum SampleScope {
    public static func resolve<Element>(_ items: [Element], isSample: (Element) -> Bool) -> SampleScoped<Element> {
        let real = items.filter { !isSample($0) }
        if real.isEmpty, !items.isEmpty { return SampleScoped(items: items, isSample: true) }
        return SampleScoped(items: real, isSample: false)
    }

    public static func sessions(_ documents: [SessionDocument]) -> SampleScoped<SessionDocument> {
        resolve(documents) { $0.sample != nil }
    }

    public static func summaries(_ summaries: [SessionSummary]) -> SampleScoped<SessionSummary> {
        resolve(summaries, isSample: \.sample)
    }

    public static func equipment(_ documents: [EquipmentDocument]) -> SampleScoped<EquipmentDocument> {
        resolve(documents) { $0.sample != nil }
    }

    public static func practicePlans(_ documents: [PracticePlanDocument]) -> SampleScoped<PracticePlanDocument> {
        resolve(documents) { $0.sample == true }
    }
}
