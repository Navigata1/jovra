import JovraBenchmark
import Testing

/// Hand-worked examples of the eventTimes task (matching rule in spec/reference/jovra_ref/benchmark.py).
@Suite("eventTimes scoring")
struct EventTimesScoringTests {
    static func ms(_ value: Int64) -> RationalTime { RationalTime(value: value, timescale: 1000) }
    let task = EventTimesTask(tolerance: RationalTime(value: 50, timescale: 1000))

    func metric(_ name: String, in metrics: [MetricResult]) throws -> MetricResult {
        try #require(metrics.first { $0.name == name })
    }

    @Test("4 predictions, 3 truth events, 50 ms tolerance: 2 matches, P 0.5000, R 0.6667, MAE 7.000 ms")
    func workedExample() throws {
        let metrics = try task.score([.init(truth: [Self.ms(1000), Self.ms(2000), Self.ms(3000)],
                                            predictions: [Self.ms(1004), Self.ms(2100), Self.ms(2990), Self.ms(5000)])])
        #expect(try metric("precision", in: metrics).value == "0.5000")
        #expect(try metric("precision", in: metrics).exact == Rational(1, 2))
        #expect(try metric("recall", in: metrics).value == "0.6667")
        #expect(try metric("recall", in: metrics).exact == Rational(2, 3))
        #expect(try metric("onset MAE", in: metrics).value == "7.000")
        #expect(try metric("onset MAE", in: metrics).unit == "ms")
    }

    @Test("a tie in distance goes to the earlier prediction, which is then consumed")
    func tieGoesEarlier() throws {
        let metrics = try task.score([.init(truth: [Self.ms(1000)], predictions: [Self.ms(1020), Self.ms(980)])])
        #expect(try metric("precision", in: metrics).exact == Rational(1, 2))
        #expect(try metric("onset MAE", in: metrics).value == "20.000")
    }

    @Test("one prediction serves only one truth event")
    func predictionConsumed() throws {
        let metrics = try task.score([.init(truth: [Self.ms(1000), Self.ms(1030)], predictions: [Self.ms(1020)])])
        #expect(try metric("recall", in: metrics).exact == Rational(1, 2))
        #expect(try metric("onset MAE", in: metrics).value == "20.000")
    }

    @Test("an exact tolerance boundary matches; one tick past it does not")
    func toleranceBoundary() throws {
        let inside = try task.score([.init(truth: [Self.ms(1000)], predictions: [Self.ms(1050)])])
        #expect(try metric("recall", in: inside).exact == Rational(1))
        let outside = try task.score([.init(truth: [RationalTime(value: 48_000, timescale: 48_000)],
                                            predictions: [RationalTime(value: 50_401, timescale: 48_000)])])
        #expect(try metric("recall", in: outside).exact == Rational(0))
    }

    @Test("no predictions: precision and MAE are undefined (null), recall is 0")
    func undefinedMetrics() throws {
        let metrics = try task.score([.init(truth: [Self.ms(1000)], predictions: [])])
        #expect(try metric("precision", in: metrics).exact == nil)
        #expect(try metric("precision", in: metrics).value == nil)
        #expect(try metric("onset MAE", in: metrics).value == nil)
        #expect(try metric("recall", in: metrics).value == "0.0000")
    }

    @Test("clips pool: matches, predictions and truth events add up across clips")
    func pooling() throws {
        let metrics = try task.score([
            .init(truth: [Self.ms(1000)], predictions: [Self.ms(1010)]),
            .init(truth: [Self.ms(1000), Self.ms(2000)], predictions: [Self.ms(2030), Self.ms(4000)]),
        ])
        #expect(try metric("precision", in: metrics).exact == Rational(2, 3))
        #expect(try metric("recall", in: metrics).exact == Rational(2, 3))
        #expect(try metric("onset MAE", in: metrics).value == "20.000")
    }
}
