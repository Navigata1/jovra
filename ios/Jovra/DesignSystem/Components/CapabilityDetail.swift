import JovraCore
import SwiftUI

/// The capability registry the app reads (ADR-0004): the copy bundled with JovraCore. A test, preview
/// or gallery injects another with `.environment(\.capabilityRegistry, ...)`. Nil only if the bundled
/// document failed to decode, which the views show as an error rather than guessing.
private struct CapabilityRegistryKey: EnvironmentKey {
    static let defaultValue: CapabilityRegistry? = try? CapabilityRegistry.bundled()
}

extension EnvironmentValues {
    var capabilityRegistry: CapabilityRegistry? {
        get { self[CapabilityRegistryKey.self] }
        set { self[CapabilityRegistryKey.self] = newValue }
    }
}

/// N12 "How this was measured", as plain values read from one registry entry: status, method
/// version, configuration band (what it was tested on), the latest benchmark or "Not benchmarked".
struct CapabilityDetailPresentation: Equatable {
    let id: String
    let title: String
    /// "Estimated", "Off until it passes testing", ...
    let status: String
    let badge: ProvenanceBadge.Kind?
    /// The registry's short UI label ("Estimated average speed, contact→bounce").
    let summary: String
    let method: String
    /// "serveSpeed.manualAssisted@1.0.0".
    let methodVersion: String
    /// What it needs to work: "Video", "Microphone", "Court calibration".
    let needs: [String]
    /// Capabilities it builds on, by title.
    let buildsOn: [String]
    /// The configuration band: the dataset of the latest benchmark, or "Not tested yet".
    let testedOn: String
    /// "Passed on Mar 2, 2027", "Did not pass on …" or "Not benchmarked".
    let benchmark: String
    /// "Mean absolute error: 3.1 mph".
    let results: [String]
    /// What a benchmark must show before the status can change.
    let promotionGate: String?
    let notes: String?
    let needsReview: Bool

    init?(id: String, registry: CapabilityRegistry) {
        guard let capability = registry.capability(id: id) else { return nil }
        self.id = id
        title = capability.title
        status = Self.statusText(capability.status)
        badge = ProvenanceBadge.Kind(status: capability.status)
        summary = capability.uiLabel
        method = capability.method
        methodVersion = "\(capability.id)@\(capability.version)"
        var needs: [String] = []
        if capability.requires.video { needs.append(String(localized: "Video", table: "DesignSystem.Components")) }
        if capability.requires.microphone { needs.append(String(localized: "Microphone", table: "DesignSystem.Components")) }
        if capability.requires.calibration { needs.append(String(localized: "Court calibration", table: "DesignSystem.Components")) }
        self.needs = needs
        buildsOn = (capability.requires.capabilities ?? []).map { registry.capability(id: $0)?.title ?? $0 }
        let benchmark = capability.lastBenchmark.value
        testedOn = benchmark?.dataset ?? String(localized: "Not tested yet", table: "DesignSystem.Components")
        if let benchmark {
            let date = Self.date(benchmark.at)
            self.benchmark = benchmark.passed
                ? String(localized: "Passed on \(date)", table: "DesignSystem.Components", comment: "Benchmark result and its date")
                : String(localized: "Did not pass on \(date)", table: "DesignSystem.Components", comment: "Benchmark result and its date")
            results = benchmark.results.map { "\($0.name): \($0.value)" }
        } else {
            self.benchmark = String(localized: "Not benchmarked", table: "DesignSystem.Components")
            results = []
        }
        promotionGate = capability.gate.value?.minimumData
        notes = capability.notes
        needsReview = capability.outputsNeedReview
    }

    static func statusText(_ status: CapabilityCapabilityStatus) -> String {
        switch status {
        case .manual: String(localized: "Manual", table: "DesignSystem.Components")
        case .estimated: String(localized: "Estimated", table: "DesignSystem.Components")
        case .validated: String(localized: "Validated", table: "DesignSystem.Components")
        case .disabled: String(localized: "Off until it passes testing", table: "DesignSystem.Components")
        case .unsupported: String(localized: "Not available", table: "DesignSystem.Components")
        }
    }

    /// "Mar 2, 2027" in UTC, so the date never shifts with the reader's time zone.
    private static func date(_ iso: String) -> String {
        guard let date = try? Date(iso, strategy: .iso8601) else { return iso }
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        style.timeZone = .gmt
        return date.formatted(style)
    }
}

/// The content of the capability detail sheet, rendered from the injected registry.
struct CapabilityDetailView: View {
    var capabilityID: String
    @Environment(\.capabilityRegistry) private var registry

    var body: some View {
        if let registry, let detail = CapabilityDetailPresentation(id: capabilityID, registry: registry) {
            CapabilityDetailContent(detail: detail)
        } else {
            StateCard(
                symbol: "questionmark.circle",
                title: String(localized: "This explanation isn't available", table: "DesignSystem.Components"),
                message: String(localized: "JOVRA couldn't find how this was measured. Your recordings and numbers are not affected.",
                                table: "DesignSystem.Components"))
        }
    }
}

private struct CapabilityDetailContent: View {
    var detail: CapabilityDetailPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            VStack(alignment: .leading, spacing: Space.x1 + Space.half) {
                Text(verbatim: detail.title)
                    .font(.jovraHeadline)
                    .foregroundStyle(.jovra(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("capability.title")
                HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
                    if let badge = detail.badge {
                        ProvenanceBadge(kind: badge)
                    } else {
                        Label { Text(verbatim: detail.status) } icon: { Image(systemName: "nosign").accessibilityHidden(true) }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.jovra(.textPrimary))
                            .padding(.horizontal, Space.x1 + 2)
                            .padding(.vertical, Space.half)
                            .background(Color.jovra(.surfaceSunken), in: Capsule())
                            .fixedSize()
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Status", tableName: "DesignSystem.Components"))
                .accessibilityValue(Text(verbatim: detail.status))
                .accessibilityIdentifier("capability.status")
                Text(verbatim: detail.summary)
                    .font(.jovraBody)
                    .foregroundStyle(.jovra(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }

            section(String(localized: "How it works", table: "DesignSystem.Components")) {
                Text(verbatim: detail.method).font(.jovraBody).foregroundStyle(.jovra(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                if detail.needsReview {
                    Label(String(localized: "Every result waits for your review.", table: "DesignSystem.Components"),
                          systemImage: "checklist")
                        .font(.subheadline).foregroundStyle(.jovra(.textSecondary))
                }
            }

            section(String(localized: "What it needs", table: "DesignSystem.Components")) {
                if detail.needs.isEmpty, detail.buildsOn.isEmpty {
                    Text("Only what you enter.", tableName: "DesignSystem.Components")
                        .font(.jovraBody).foregroundStyle(.jovra(.textPrimary))
                }
                ForEach(detail.needs, id: \.self) { need in
                    Label { Text(verbatim: need) } icon: { Image(systemName: "smallcircle.filled.circle").accessibilityHidden(true) }
                        .font(.jovraBody).foregroundStyle(.jovra(.textPrimary))
                }
                if !detail.buildsOn.isEmpty {
                    // The capabilities whose results this one uses, named by their own titles.
                    fact(String(localized: "Builds on", table: "DesignSystem.Components"),
                         ListFormatter.localizedString(byJoining: detail.buildsOn), id: "capability.buildsOn")
                        .padding(.top, Space.half)
                }
            }

            section(String(localized: "How well it works", table: "DesignSystem.Components")) {
                fact(String(localized: "Tested on", table: "DesignSystem.Components"), detail.testedOn, id: "capability.testedOn")
                fact(String(localized: "Latest benchmark", table: "DesignSystem.Components"), detail.benchmark, id: "capability.benchmark")
                ForEach(detail.results, id: \.self) { result in
                    Text(verbatim: result).font(.jovraBody.monospacedDigit()).foregroundStyle(.jovra(.textPrimary))
                }
                if let gate = detail.promotionGate {
                    fact(String(localized: "To be promoted it must pass", table: "DesignSystem.Components"), gate, id: "capability.gate")
                }
            }

            section(String(localized: "What JOVRA doesn't do", table: "DesignSystem.Components")) {
                // States what one camera cannot measure (CLAUDE.md rule 1), so the copy lint allows the words.
                Text("No line calls. No spin readings. No 3D biomechanics. No injury or medical advice.", tableName: "DesignSystem.Components") // copy-lint: allow line-call — states what JOVRA does not do; copy-lint: allow injury — states what JOVRA does not do
                    .font(.jovraBody).foregroundStyle(.jovra(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                if let notes = detail.notes {
                    Text(verbatim: notes).font(.subheadline).foregroundStyle(.jovra(.textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            fact(String(localized: "Method version", table: "DesignSystem.Components"), detail.methodVersion, id: "capability.methodVersion",
                 monospaced: true)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text(title)
                .font(.jovraLabel.weight(.semibold))
                .foregroundStyle(.jovra(.textPrimary))
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .jovraCard()
    }

    private func fact(_ label: String, _ value: String, id: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.footnote).foregroundStyle(.jovra(.textSecondary))
            Text(verbatim: value)
                .font(monospaced ? .jovraTimecode : .jovraBody)
                .foregroundStyle(.jovra(.textPrimary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityValue(Text(verbatim: value))
        .accessibilityIdentifier(id)
    }
}
