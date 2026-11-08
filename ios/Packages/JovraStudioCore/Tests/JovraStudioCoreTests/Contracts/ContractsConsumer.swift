import JovraStudioCore

/// STU-01 (S10): the strict decoders for every Studio record and contract data file modelled in
/// Sources/JovraStudioCore/Contracts. Later modules register their own decoders and vector checkers in their own
/// `<Name>Consumer.swift` files.
struct ContractsConsumer: StudioFixtureConsumer {
    var decoders: [StudioContractDecoder] { StudioContracts.decoders }
}
