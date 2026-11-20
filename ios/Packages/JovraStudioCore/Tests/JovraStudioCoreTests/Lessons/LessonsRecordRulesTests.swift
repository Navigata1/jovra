import Foundation
import JovraCore
import JovraStudioCore
import Testing

/// The `jovra.lesson/1` record rules (`spec/reference/studio/records.py` check_lesson): the three Sample lessons pass
/// and round-trip, and every lesson invalid case is refused with the code the reference gives.
@Suite("Lessons: record rules")
struct LessonsRecordRulesTests {
    static let samples = ["lesson.2026-09-09.json", "lesson.2026-09-23.json", "lesson.2026-10-07.json"]

    @Test("the three Sample lesson records pass the rules and round-trip byte for byte", arguments: samples)
    func sampleLessonsRoundTrip(name: String) throws {
        let bytes = try StudioFixtures.data("records/\(name)")
        let lesson = try StudioContractCodec.decode(Lesson.self, from: bytes)
        try LessonRules.check(lesson)
        #expect(lesson.sample)
        #expect(try StudioContractCodec.encode(lesson) == CanonicalJSON.canonicalize(bytes))
    }

    @Test("every lesson invalid case is refused: schema cases by the decoder, reference cases with their code")
    func invalidCasesAreRefused() throws {
        var seen: [String: String] = [:]
        for file in ["lesson.2026-09-23.invalid.json", "lesson.2026-10-07.invalid.json"] {
            let doc = try StudioJSONParser.parse(StudioFixtures.data("invalid/\(file)"))
            guard case .string(let base)? = doc["base"], case .array(let cases)? = doc["cases"] else {
                Issue.record("\(file) is malformed"); continue
            }
            let record = try StudioJSONParser.parse(StudioFixtures.data(base))
            for item in cases {
                guard case .string(let id)? = item["id"], let patch = item["patch"], let expect = item["expect"],
                      case .string(let layer)? = expect["layer"] else { Issue.record("\(file): malformed case"); continue }
                let bad = try StudioJSONPatch.apply(patch, to: record).serialized()
                if layer == "schema" {
                    #expect(throws: StudioContractError.self, "\(id)") { _ = try StudioContractCodec.decode(Lesson.self, from: bad) }
                    seen[id] = "schema"
                    continue
                }
                guard case .string(let code)? = expect["code"] else { Issue.record("\(id) has no code"); continue }
                let lesson = try StudioContractCodec.decode(Lesson.self, from: bad)
                do throws(LessonRejection) {
                    try LessonRules.check(lesson)
                    Issue.record("\(id): accepted, expected \(code)")
                } catch {
                    #expect(error.code.rawValue == code, "\(id): \(error)")
                    seen[id] = error.code.rawValue
                }
            }
        }
        print("Lesson invalid cases refused: \(seen.sorted { $0.key < $1.key })")
        #expect(seen == ["unattributed-coach-note": "unattributedCoach", "over-done": "badPractice",
                         "pending-marked-done": "badPractice", "cue-on-unknown-clip": "unknownClip",
                         "id-trailing-newline": "schema", "estimate-marked-reviewed": "provenanceMismatch"])
    }

    @Test("the reference's other lesson rules hold: duplicate ids, sourceless clips, empty windows, private grants")
    func otherRules() throws {
        let base = try StudioContractCodec.decode(Lesson.self, from: StudioFixtures.data("records/lesson.2026-10-07.json"))
        var duplicate = base
        duplicate.clips.append(duplicate.clips[0])
        var sourceless = base
        sourceless.clips[1].sourceId = .null
        sourceless.clips[1].sessionId = .null
        var window = base
        window.clips[1].window = .value(StudioIntervalUs(startUs: 5, endUs: 5))
        var grants = base
        grants.share.grantIds = ["g-1"]
        var reviewedNoReviewer = base
        reviewedNoReviewer.cues[0].reviewedBy = .null
        for (lesson, code) in [(duplicate, LessonRejection.Code.duplicateId), (sourceless, .clipWithoutSource),
                               (window, .badInterval), (grants, .badShare), (reviewedNoReviewer, .provenanceMismatch)] {
            #expect(throws: LessonRejection.self) { try LessonRules.check(lesson) }
            do throws(LessonRejection) { try LessonRules.check(lesson) } catch { #expect(error.code == code) }
        }
    }

    @Test("JOVRA can never author a note: the author enum is exactly user and coach, and 'jovra' is refused on read")
    func noJovraAuthor() throws {
        // Compile-time: `LessonNoteAuthor` has no case for JOVRA, so `LessonNote(author: .jovra, ...)` cannot be
        // written; `LessonAttribution` switches over it exhaustively, so adding a case would not compile silently.
        #expect(LessonNoteAuthor.allCases == [.user, .coach])
        let bytes = try StudioFixtures.data("records/lesson.2026-09-09.json")
        let text = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: #""author": "user""#, with: #""author": "jovra""#)
        #expect(text.contains(#""author": "jovra""#))
        #expect(throws: StudioContractError.self) { _ = try StudioContractCodec.decode(Lesson.self, from: Data(text.utf8)) }
    }
}
