import JovraCore

extension PlacementWords {
    /// What VoiceOver reads for a placement, localized: "Deep cross-court, in" (story 364). The English catalog
    /// values equal `englishSentence`, which `spec/fixtures/calibration/C09-placement-words.json` pins.
    var spoken: String {
        let depthWord = switch depth {
        case .short: String(localized: "Short", table: "DesignSystem.Court", comment: "Placement depth: inside the service line")
        case .deep: String(localized: "Deep", table: "DesignSystem.Court", comment: "Placement depth: between the service line and the baseline")
        case .long: String(localized: "Long", table: "DesignSystem.Court", comment: "Placement depth: beyond the baseline")
        }
        let directionWord = switch direction {
        case .crossCourt: String(localized: "cross-court", table: "DesignSystem.Court", comment: "Placement direction, after the depth word")
        case .downTheLine: String(localized: "down the line", table: "DesignSystem.Court", comment: "Placement direction, after the depth word")
        case .middle: String(localized: "middle", table: "DesignSystem.Court", comment: "Placement direction: the central third of the court")
        case .left: String(localized: "left", table: "DesignSystem.Court", comment: "Placement side as seen from the hitter's end")
        case .right: String(localized: "right", table: "DesignSystem.Court", comment: "Placement side as seen from the hitter's end")
        }
        let resultWord = switch result {
        case .in: String(localized: "in", table: "DesignSystem.Court", comment: "Placement result, lower case at the end of a sentence")
        case .out: String(localized: "out", table: "DesignSystem.Court", comment: "Placement result, lower case at the end of a sentence")
        case .needsReview: String(localized: "needs review", table: "DesignSystem.Court", comment: "Placement result, lower case at the end of a sentence")
        }
        if wide {
            return String(format: String(localized: "%1$@ %2$@, wide, %3$@", table: "DesignSystem.Court",
                                         comment: "A placement read aloud beyond the sideline: depth, direction, result (Deep cross-court, wide, out)"),
                          depthWord, directionWord, resultWord)
        }
        return String(format: String(localized: "%1$@ %2$@, %3$@", table: "DesignSystem.Court",
                                     comment: "A placement read aloud: depth, direction, result (Deep cross-court, in)"),
                      depthWord, directionWord, resultWord)
    }
}
