import Foundation
import JovraCore
import JovraStudioCore
import Testing

/// ProgressStoryBuilder (S36, user stories 134 and 135): percentage-point comparisons that are dropped, never spun,
/// when the two scopes are not comparable.
@Suite("Lessons: Progress Story comparisons")
struct LessonsProgressTests {
    @Test("every progress-comparison vector reproduces the reference output and its hand-derived assertions")
    func everyVectorPasses() throws {
        let cases = try LessonsProgressVectors.cases()
        #expect(cases.count == 20)
        for (id, item) in cases {
            do { try LessonsProgressVectors.check(item) } catch { Issue.record("\(id): \(error)") }
        }
    }

    @Test("a method change and a differing selection each drop the comparison to a chronology", arguments: [
        ("later-method-version-changed", ProgressReason.methodChange),
        ("later-capability-version-changed", .methodChange),
        ("user-chosen-one-side", .differingSelection),
        ("seeded-random-vs-all", .differingSelection),
    ])
    func methodChangeAndDifferingSelection(id: String, reason: ProgressReason) throws {
        let item = try #require(LessonsProgressVectors.cases().first { $0.id == id }).item
        let c = try ProgressStoryBuilder.compare("first-serve-in-pct", earlier: ProgressScope(json: #require(item["input"]?["earlier"])),
                                                 later: ProgressScope(json: #require(item["input"]?["later"])))
        #expect(!c.comparable)
        #expect(c.reasons.contains(reason))
        #expect(c.claim == .chronology)
        #expect(c.deltaPercentagePoints == nil && c.deltaDisplay == nil && c.summary == nil)
        // the dated fractions stay as facts
        #expect(c.earlier.display == "12 / 30 · 40%" && c.later.display == "18 / 30 · 60%")
    }

    @Test("story 134: the Sample serve practice reads 12 / 30 · 40% → 18 / 30 · 60%, +20 percentage points")
    func sampleServePractice() throws {
        let c = try ProgressStoryBuilder.compare("first-serve-in-pct", earlier: Self.scope("2026-09-09", 12, 30),
                                                 later: Self.scope("2026-10-07", 18, 30))
        #expect(c.summary == "12 / 30 · 40% → 18 / 30 · 60%, +20 percentage points")
        #expect(c.deltaPercentagePoints == 20)
        #expect(c.claim == .change)
        // the core Fraction (RateRatio) and pct carry each side
        #expect(c.earlier.fraction == RateRatio(n: 12, d: 30, pct: .value(40), display: "40%"))
    }

    @Test("no output words a percentage improvement, whatever the change")
    func noImprovementWording() throws {
        for (n1, n2) in [(1, 29), (29, 1), (15, 15), (0, 30)] {
            let c = try ProgressStoryBuilder.compare("first-serve-in-pct", earlier: Self.scope("2026-09-09", n1, 30),
                                                     later: Self.scope("2026-10-07", n2, 30))
            let text = [c.summary, c.deltaDisplay, c.earlier.display, c.later.display].compactMap { $0 }.joined(separator: " ")
            #expect(!text.lowercased().contains("improve"))
            #expect(!text.contains("% improvement"))
        }
    }

    @Test("a scope with an unknown field, a bad date or no session is refused as badScope")
    func malformedScopes() throws {
        let base = try #require(LessonsProgressVectors.cases().first).item
        let earlier = try #require(base["input"]?["earlier"])
        for patch in [
            #"[{"op": "add", "path": "/extra", "value": 1}]"#,
            #"[{"op": "replace", "path": "/date", "value": "2026-02-30"}]"#,
            #"[{"op": "replace", "path": "/sessionIds", "value": []}]"#,
            #"[{"op": "replace", "path": "/numerator", "value": 12.0}]"#,
            #"[{"op": "replace", "path": "/selectionRule", "value": "best"}]"#,
        ] {
            let bad = try StudioJSONPatch.apply(StudioJSONParser.parse(Data(patch.utf8)), to: earlier)
            #expect(throws: ProgressRejection.self, "\(patch)") { _ = try ProgressScope(json: bad) }
            do throws(ProgressRejection) { _ = try ProgressScope(json: bad) } catch { #expect(error.code == .badScope) }
        }
    }

    @Test("the progress page says swift: consumed, and the manifest passes only while this checker is registered")
    func progressPageIsConsumed() throws {
        let page = try String(contentsOf: StudioFixtures.repositoryRoot().appendingPathComponent("spec/studio/modules/progress.md"),
                              encoding: .utf8)
        #expect(page.contains("\nswift: consumed\n"))
        let report = try ContractsFixtureManifestTests.check(ContractsFixtureManifestTests.root)
        #expect(report.failures.isEmpty, "\(report.failures)")
        #expect(report.rows.contains(.init(kind: "progress-comparison", page: "progress", swift: "consumed", consumed: true, files: 1)))
        var without = StudioConsumption.discovered.kinds
        without.remove("progress-comparison")
        let missing = try ContractsFixtureManifestTests.check(ContractsFixtureManifestTests.root, consumed: without)
        #expect(missing.failures == ["page progress says swift: consumed, but kind progress-comparison has no registered Swift consumer"])
    }

    static func scope(_ date: String, _ n: Int, _ d: Int) -> ProgressScope {
        ProgressScope(date: date, sessionIds: ["s-\(date)"], sessionKind: "practice", statDefinitionId: "first-serve-in-pct",
                      method: ProgressMethod(methodId: "manual-tagging-v1", methodVersion: "1", capabilityVersion: nil),
                      selectionRule: .all, numerator: n, denominator: d, provenance: .reviewed)
    }
}
