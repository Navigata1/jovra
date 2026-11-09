import Foundation
import JovraStudioCore

/// STU-10 (S35): KeeperSelector and staleness propagation consume the shared `keepers` and `staleness` vectors
/// (spec/reference/studio/keepers.py, staleness.py). `jovra.keeper-catalog/1` itself is decoded by ContractsConsumer.
struct KeepersConsumer: StudioFixtureConsumer {
    var vectorCheckers: [String: @Sendable (StudioJSONValue) throws -> Void] {
        [
            "keepers": { try KeepersVectors.checkKeepers($0) },
            "staleness": { try KeepersVectors.checkStaleness($0) },
        ]
    }
}
