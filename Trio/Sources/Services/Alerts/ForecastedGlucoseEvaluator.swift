import Foundation

/// Picks a predicted-glucose value at a fixed horizon across the available
/// `Determination.predictions` curves (IOB / COB / UAM / ZT).
///
/// Mirrors the multi-curve selection in the oref-swift port
/// (`ForecastGenerator.blendForecasts`) but at a single index instead of
/// across the post-peak window. The Trio determination JSON already holds
/// every curve at 5-min increments, so index 4 ≈ +20 min.
///
/// Reduction direction is selectable per call via `Direction` — `min` is
/// conservative for low detection (the original, still-default behavior);
/// `max` is conservative for high detection, and is the same reduction
/// oref-swift's own blender (`ForecastGenerator.blendForecasts`) uses for SMB
/// dosing safety.
enum ForecastedGlucoseEvaluator {
    static let defaultHorizonMinutes = 20

    enum Curve: String { case iob, cob, uam, zt }

    /// Which reduction to apply across the sampled curves at the horizon.
    /// `.low` takes the `min` (conservative for low detection, the original
    /// behavior); `.high` takes the `max` (conservative for high detection,
    /// matching oref-swift's `ForecastGenerator.blendForecasts` SMB-safety reduction).
    enum Direction { case low, high }

    struct Result: Equatable {
        let predictedGlucose: Decimal
        let horizonMinutes: Int
        let curvesUsed: Set<Curve>
        let perCurve: [Curve: Decimal]
        let direction: Direction
    }

    static func evaluate(
        determination: Determination,
        horizonMinutes: Int = defaultHorizonMinutes,
        direction: Direction = .low
    ) -> Result? {
        let index = horizonMinutes / 5
        guard let predictions = determination.predictions else { return nil }

        var samples: [Curve: Decimal] = [:]
        if let v = sample(predictions.iob, at: index) { samples[.iob] = v }
        if let v = sample(predictions.cob, at: index) { samples[.cob] = v }
        if let v = sample(predictions.uam, at: index) { samples[.uam] = v }
        if let v = sample(predictions.zt, at: index) { samples[.zt] = v }
        let reduced = direction == .low ? samples.values.min() : samples.values.max()
        guard let reduced else { return nil }

        return Result(
            predictedGlucose: reduced,
            horizonMinutes: horizonMinutes,
            curvesUsed: Set(samples.keys),
            perCurve: samples,
            direction: direction
        )
    }

    private static func sample(_ array: [Int]?, at index: Int) -> Decimal? {
        guard let array, array.indices.contains(index) else { return nil }
        return Decimal(array[index])
    }
}
