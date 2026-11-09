// fixture-kind: jovra.sampleAnalysis
import Foundation
@testable import JovraCore

/// Every analysis overlay decodes as SampleAnalysisRecord and re-encodes to the same canonical bytes.
struct SampleAnalysisRecordRunner: FixtureRunner {
    let kind = "jovra.sampleAnalysis"
    func run(_ data: Data, path: URL) throws { try roundTripRecord(SampleAnalysisRecord.self, data: data, path: path) }
}
