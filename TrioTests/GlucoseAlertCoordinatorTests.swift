import Foundation
import Testing

@testable import Trio

@Suite("Trio Alerts: GlucoseAlertCoordinator breach/retract") struct GlucoseAlertCoordinatorTests {
    @Test("low breaches at or below threshold 70") func lowBreach() {
        #expect(GlucoseAlertCoordinator.breached(type: .low, latestMgDL: 70, thresholdMgDL: 70))
        #expect(!GlucoseAlertCoordinator.breached(type: .low, latestMgDL: 71, thresholdMgDL: 70))
    }

    @Test("low retracts only at threshold + margin (70 + 5)") func lowRetract() {
        #expect(!GlucoseAlertCoordinator.shouldRetract(
            type: .low, latestMgDL: 74, thresholdMgDL: 70, recoveryMarginMgDL: 5
        ))
        #expect(GlucoseAlertCoordinator.shouldRetract(
            type: .low, latestMgDL: 75, thresholdMgDL: 70, recoveryMarginMgDL: 5
        ))
    }

    @Test("urgentLow breaches at or below threshold 54") func urgentLowBreach() {
        #expect(GlucoseAlertCoordinator.breached(type: .urgentLow, latestMgDL: 54, thresholdMgDL: 54))
        #expect(!GlucoseAlertCoordinator.breached(type: .urgentLow, latestMgDL: 55, thresholdMgDL: 54))
    }

    @Test("high breaches at or above threshold 270") func highBreach() {
        #expect(GlucoseAlertCoordinator.breached(type: .high, latestMgDL: 270, thresholdMgDL: 270))
        #expect(!GlucoseAlertCoordinator.breached(type: .high, latestMgDL: 269, thresholdMgDL: 270))
    }

    @Test("high retracts only at threshold - margin (270 - 5)") func highRetract() {
        #expect(!GlucoseAlertCoordinator.shouldRetract(
            type: .high, latestMgDL: 266, thresholdMgDL: 270, recoveryMarginMgDL: 5
        ))
        #expect(GlucoseAlertCoordinator.shouldRetract(
            type: .high, latestMgDL: 265, thresholdMgDL: 270, recoveryMarginMgDL: 5
        ))
    }

    @Test("forecastedHigh breaches at or above threshold 270") func forecastedHighBreach() {
        #expect(GlucoseAlertCoordinator.breached(type: .forecastedHigh, latestMgDL: 270, thresholdMgDL: 270))
        #expect(GlucoseAlertCoordinator.breached(type: .forecastedHigh, latestMgDL: 271, thresholdMgDL: 270))
        #expect(!GlucoseAlertCoordinator.breached(type: .forecastedHigh, latestMgDL: 269, thresholdMgDL: 270))
    }

    @Test("forecastedHigh retracts only at threshold - margin (270 - 5)") func forecastedHighRetract() {
        #expect(!GlucoseAlertCoordinator.shouldRetract(
            type: .forecastedHigh, latestMgDL: 266, thresholdMgDL: 270, recoveryMarginMgDL: 5
        ))
        #expect(GlucoseAlertCoordinator.shouldRetract(
            type: .forecastedHigh, latestMgDL: 265, thresholdMgDL: 270, recoveryMarginMgDL: 5
        ))
    }

    @Test("type priority order: urgentLow < low < forecastedLow < high < forecastedHigh < carbsRequired") func priorityOrder() {
        #expect(GlucoseAlertType.urgentLow.priority == 0)
        #expect(GlucoseAlertType.low.priority == 1)
        #expect(GlucoseAlertType.forecastedLow.priority == 2)
        #expect(GlucoseAlertType.high.priority == 3)
        #expect(GlucoseAlertType.forecastedHigh.priority == 4)
        #expect(GlucoseAlertType.carbsRequired.priority == 5)
        #expect(GlucoseAlertType.urgentLow.priority < GlucoseAlertType.low.priority)
    }

    @Test("shouldRetract uses the default 5 mg/dL margin when omitted") func defaultMarginWiring() {
        #expect(GlucoseAlertCoordinator.shouldRetract(type: .low, latestMgDL: 75, thresholdMgDL: 70))
        #expect(!GlucoseAlertCoordinator.shouldRetract(type: .low, latestMgDL: 74, thresholdMgDL: 70))
    }

    // MARK: - Carbs Required predicates (mg/dL-based gates are no-ops)

    /// Carbs Required is determination-driven (`evaluateCarbsRequired(_:)`),
    /// not reading-driven. The shared mg/dL `breached` predicate must never
    /// return true for it, regardless of value / threshold combination.
    @Test("carbsRequired never breaches via the mg/dL predicate") func carbsRequiredNeverBreaches() {
        #expect(!GlucoseAlertCoordinator.breached(type: .carbsRequired, latestMgDL: 0, thresholdMgDL: 0))
        #expect(!GlucoseAlertCoordinator.breached(type: .carbsRequired, latestMgDL: 200, thresholdMgDL: 10))
        #expect(!GlucoseAlertCoordinator.breached(type: .carbsRequired, latestMgDL: 10, thresholdMgDL: 200))
    }

    @Test("carbsRequired never retracts via the mg/dL predicate") func carbsRequiredNeverRetractsViaMgDL() {
        #expect(!GlucoseAlertCoordinator.shouldRetract(
            type: .carbsRequired, latestMgDL: 100, thresholdMgDL: 10, recoveryMarginMgDL: 5
        ))
        #expect(!GlucoseAlertCoordinator.shouldRetract(
            type: .carbsRequired, latestMgDL: 0, thresholdMgDL: 50, recoveryMarginMgDL: 5
        ))
    }

    // MARK: - forecastedHigh evaluator + breached/shouldRetract composition
    //
    // `GlucoseAlertCoordinator.evaluateForecastBased` (private, driven by
    // `determinationDidUpdate`) has no test harness in this suite — there is
    // no mock `TrioAlertManager` to drive it end-to-end, and the low-forecast
    // path has never had one either. These tests instead compose the two
    // pure pieces it wires together (`ForecastedGlucoseEvaluator.evaluate`
    // and `GlucoseAlertCoordinator.breached`/`shouldRetract`) exactly the way
    // `evaluateForecastBased` does, at the real threshold (270) and margin (5).

    private func makeHighDetermination(iob: [Decimal]) -> Determination {
        Determination(
            id: nil,
            reason: "",
            units: nil,
            insulinReq: nil,
            eventualBG: nil,
            sensitivityRatio: nil,
            rate: nil,
            duration: nil,
            iob: nil,
            cob: nil,
            predictions: Predictions(iob: iob, zt: nil, cob: nil, uam: nil),
            deliverAt: nil,
            carbsReq: nil,
            temp: nil,
            bg: nil,
            reservoir: nil,
            isf: nil,
            timestamp: nil,
            tdd: nil,
            current_target: nil,
            minDelta: nil,
            expectedDelta: nil,
            minGuardBG: nil,
            minPredBG: nil,
            threshold: nil,
            carbRatio: nil,
            received: nil
        )
    }

    @Test("forecastedHigh fires when the max forecast at +20min is at or above threshold 270")
    func forecastedHighComposedFires() {
        let determination = makeHighDetermination(iob: [100, 101, 102, 103, 270])
        let result = ForecastedGlucoseEvaluator.evaluate(determination: determination, direction: .high)
        #expect(result != nil)
        #expect(GlucoseAlertCoordinator.breached(
            type: .forecastedHigh, latestMgDL: result!.predictedGlucose, thresholdMgDL: 270
        ))
    }

    @Test("forecastedHigh does not fire when the max forecast at +20min is below threshold 270")
    func forecastedHighComposedDoesNotFire() {
        let determination = makeHighDetermination(iob: [100, 101, 102, 103, 269])
        let result = ForecastedGlucoseEvaluator.evaluate(determination: determination, direction: .high)
        #expect(result != nil)
        #expect(!GlucoseAlertCoordinator.breached(
            type: .forecastedHigh, latestMgDL: result!.predictedGlucose, thresholdMgDL: 270
        ))
    }

    @Test("forecastedHigh retracts once the forecast drops to threshold - margin (265)")
    func forecastedHighComposedRetracts() {
        let stillBreached = makeHighDetermination(iob: [100, 101, 102, 103, 266])
        let stillBreachedResult = ForecastedGlucoseEvaluator.evaluate(determination: stillBreached, direction: .high)
        #expect(stillBreachedResult != nil)
        #expect(!GlucoseAlertCoordinator.shouldRetract(
            type: .forecastedHigh, latestMgDL: stillBreachedResult!.predictedGlucose, thresholdMgDL: 270
        ))

        let recovered = makeHighDetermination(iob: [100, 101, 102, 103, 265])
        let recoveredResult = ForecastedGlucoseEvaluator.evaluate(determination: recovered, direction: .high)
        #expect(recoveredResult != nil)
        #expect(GlucoseAlertCoordinator.shouldRetract(
            type: .forecastedHigh, latestMgDL: recoveredResult!.predictedGlucose, thresholdMgDL: 270
        ))
    }
}

/// Guards the #1428 invariant: "Use CGM App Alerts" suppression applies to
/// reading-driven alarms only. A CGM app can alarm on the current reading,
/// but it cannot compute Trio's oref forecast or carbsReq, so those alarms
/// must stay armed — which is also what the settings screen shows the user,
/// since only reading-driven types move into the "Handled by CGM App" section.
@Suite("Trio Alerts: CGM-ownership suppression scope") struct CGMOwnershipSuppressionScopeTests {
    @Test("Forecast and carbs-required alarms are not reading-driven") func determinationDrivenTypes() {
        #expect(!GlucoseAlertType.forecastedLow.isReadingDriven)
        #expect(!GlucoseAlertType.forecastedHigh.isReadingDriven)
        #expect(!GlucoseAlertType.carbsRequired.isReadingDriven)
    }

    @Test("Only high/low/urgentLow are reading-driven") func readingDrivenSetIsExact() {
        let readingDriven = Set(GlucoseAlertType.allCases.filter(\.isReadingDriven))
        #expect(readingDriven == [.high, .low, .urgentLow])
    }
}
