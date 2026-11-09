extension CourtCalibration {
    /// Proposes a homography from independently observed painted intersections on the calibration frame.
    /// The caller supplies same-frame measurements and disjoint fit and check observations. The manual
    /// calibration stays the source of truth. Passing these observations does not certify the rest of the court.
    public func proposedRefinement(fitting observations: [CalibrationObservation], checking heldOut: [CalibrationObservation],
                                   current: CameraBinding, atMs: Int) -> Homography? {
        guard camera == current, current.width > 0, current.height > 0, atMs >= 0,
              validity(atMs: atMs, current: current) == .valid,
              observations.count >= 5, heldOut.contains(where: { $0.court.y < 0 }),
              heldOut.contains(where: { $0.court.y > 0 }) else { return nil }

        let cornerSet = Set(courtPoints)
        guard courtPoints.count == 4,
              cornerSet == Set(CourtGeometry.doublesCorners.map(\.point)) ||
                cornerSet == Set(CourtGeometry.singlesCorners.map(\.point)) else { return nil }
        let evidence = observations + heldOut
        let namedIntersections = Set(CourtIntersection.allCases.map(\.point))
        let evidencePoints = Set(evidence.map(\.court))
        let evidencePixels = Set(evidence.map(\.pixel))
        guard evidencePoints.count == evidence.count, evidencePixels.count == evidence.count,
              evidencePoints.isSubset(of: namedIntersections), evidencePoints.isDisjoint(with: cornerSet),
              evidencePixels.isDisjoint(with: imagePoints),
              evidence.allSatisfy({ (0...Double(current.width)).contains($0.pixel.x) &&
                                    (0...Double(current.height)).contains($0.pixel.y) }),
              let proposed = try? Homography.fit(image: observations.map(\.pixel), court: observations.map(\.court)) else { return nil }

        let pixelTolerance = CalibrationCheck.thresholdPx(frameHeight: current.height)
        let manualCorners = zip(courtPoints, imagePoints).map { CalibrationObservation(court: $0, pixel: $1) }
        guard evidence.allSatisfy({ agrees(homography, with: $0, within: pixelTolerance) }),
              (evidence + manualCorners).allSatisfy({ agrees(proposed, with: $0, within: pixelTolerance) }) else { return nil }

        var improved = false
        for point in heldOut {
            guard let original = unproject(point.pixel), let refined = proposed.unproject(point.pixel) else { return nil }
            let originalError = original.distance(to: point.court)
            let refinedError = refined.distance(to: point.court)
            guard refinedError <= 0.10, refinedError <= originalError else { return nil }
            improved = improved || refinedError < originalError
        }
        return improved ? proposed : nil
    }

    private func agrees(_ candidate: Homography, with observation: CalibrationObservation, within tolerance: Double) -> Bool {
        guard let projected = candidate.project(observation.court) else { return false }
        let dx = projected.x - observation.pixel.x, dy = projected.y - observation.pixel.y
        return dx * dx + dy * dy <= tolerance * tolerance
    }
}
