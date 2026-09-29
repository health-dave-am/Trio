---
type: analysis
title: High Glucose Soon Feasibility
created: 2026-09-28
tags:
  - alerts
  - glucose
  - forecastedHigh
  - issue-1594
---

## Verdict

**Mirror approach holds.** Every file that references `forecastedLow` has a
direct, symmetric analogue for a `forecastedHigh` case, and the repo-wide
grep for `GlucoseAlertType` / `forecastedLow` turned up no additional
exhaustive switches in the watch app, Live Activity, or
`BaseTrioAlertManager` — those consumers only test membership
(`GlucoseAlertType(slug:) != nil`, `== .urgentLow`) or iterate `allCases`
generically, so they compile and behave correctly with no changes.

Two deviations from a pure mirror were expected going in and are confirmed
real:

1. **`isEnabled` default.** `GlucoseAlert.init(type:)` currently hardcodes
   `isEnabled = true` for every type. `forecastedHigh` needs to seed
   disabled. This requires a new `GlucoseAlertType.defaultIsEnabled`
   computed property and a one-line change to `init(type:)` to read it
   instead of the literal `true`.
2. **Evaluator direction.** `ForecastedGlucoseEvaluator` currently always
   reduces with `min` across the four oref curves (conservative for low
   detection). `forecastedHigh` needs the same input set reduced with `max`
   (conservative for high detection, matching oref-swift's
   `ForecastGenerator.blendForecasts`). This requires a `Direction` enum
   and a parameter threaded through `evaluate(...)`, defaulting to `.low`
   so every existing call site/test keeps compiling unchanged.

One additional deviation was found during the file read that is **not**
listed in the task but should be fixed in the same pass, because it is a
silent-wrong-behavior bug rather than a compile error:

3. **`GlucoseAlertsRootView.summary(for:)`** (`Trio/Sources/Modules/GlucoseAlerts/View/GlucoseAlertsRootView.swift:296-303`)
   switches on `alarm.type` with explicit `.high` → "above" and
   `.carbsRequired` → "at least", falling through to a `default: "below"`
   for everything else. This switch has a `default` case, so it will
   **compile** without a `forecastedHigh` case, but it will silently
   describe a High Glucose Soon alarm as firing "below" its threshold,
   which is wrong. It needs `.forecastedHigh` added alongside `.high` in
   that comparator closure. Not a build-breaker, so it wasn't in the
   original touch-point list, but it is in scope for the same review.

## File-by-file touch points

| File | Touch points | Notes |
|---|---|---|
| `Trio/Sources/Models/GlucoseAlerts/GlucoseAlertType.swift` | `case forecastedHigh` inserted after `.high`; `isReadingDriven` (→ `false`, grouped with `.forecastedLow`/`.carbsRequired`); `displayName`; `blurb`; `defaultThresholdMgDL` (270); `defaultSoundFilename` (`bloom.caf`, confirmed exists at `Trio/Resources/Sounds/bloom.caf`); `defaultOverridesSilenceAndDND` (`false`, add to grouped case); new `defaultIsEnabled` property (`false` for `forecastedHigh`, `true` otherwise) | Priority becomes urgentLow(0) < low(1) < forecastedLow(2) < high(3) < forecastedHigh(4) < carbsRequired(5). Doc comment at top of enum should be updated if it lists ordering (currently it does not enumerate the order explicitly, just says "priority order"). |
| `Trio/Sources/Models/GlucoseAlerts/GlucoseAlert.swift` | `init(type:)` line 29 `isEnabled = true` → `isEnabled = type.defaultIsEnabled` | `Codable` fallback at line 66 (`decodeIfPresent ... ?? true`) stays unchanged per task instructions — previously stored alarms keep current behavior. |
| `Trio/Sources/Services/Alerts/ForecastedGlucoseEvaluator.swift` | New `enum Direction { case low, high }`; new `direction: Direction = .low` param on `evaluate(determination:horizonMinutes:)`; swap `samples.values.min()` for a direction-based `min()`/`max()`; add `let direction: Direction` to `Result` | File-level doc comment (lines 11-14) currently asserts reduction is always `min` — needs updating. |
| `Trio/Sources/Services/Alerts/GlucoseAlertCoordinator.swift` | `breached(type:...)` (lines 44-55): add `.forecastedHigh` to the `.high` case; `shouldRetract(...)` (lines 60-76): same; `evaluateReadingBased` (line 188): extend early-return to both `.forecastedLow` and `.forecastedHigh`; `evaluateForecast` (lines 206-233): add `highFamilyFiring` check mirroring `lowFamilyFiring`, extend the loop/filter to also evaluate `.forecastedHigh` alarms; `evaluateForecastBased` (lines 235-254): pass `direction:` to the evaluator and replace the hardcoded `<=` with `Self.breached(...)`; `alertID(for:)` (lines 341-354): add `case .forecastedHigh: typeSlug = "forecastedHigh"`; `bodyText(for:valueMgDL:)` (lines 356-383): add `.forecastedHigh` case with the "may go above" string | `GlucoseAlertType.init?(slug:)` uses `rawValue` so no change needed there — confirmed. File-level doc comment around line 18 describing forecastedLow horizon needs to cover both. No-CGM-ownership-guard comment in `evaluateForecast` stays as-is; applies equally to the high forecast per task decision. |
| `Trio/Sources/Services/Alerts/GlucoseAlertsStore.swift` | `defaultAlerts()` (lines 54-62): insert `GlucoseAlert(type: .forecastedHigh)` after `.high` | The `init` backfill loop (lines 33-38) iterates `GlucoseAlertType.allCases` and already appends any missing type generically — confirmed it needs no duplicate logic, just the doc-comment update the task calls for (currently says "every alarm seeds enabled", needs to say the seed honors `defaultIsEnabled`). |
| `Trio/Sources/Modules/GlucoseAlerts/View/GlucoseAlertEditorView.swift` | `switch working.type` (lines 50-56): add `case .forecastedHigh: forecastedHighBody`; new `forecastedHighBody` computed property mirroring `forecastedLowBody` (lines 151-163) | `generalSection`, `AlarmActiveSection`, `AlarmAudioSection`, delete section are all type-agnostic — confirmed via reading `body` (lines 45-77), no changes needed there. |
| `Trio/Sources/Modules/GlucoseAlerts/View/GlucoseAlertsRootView.swift` | **Not in original list, found during read:** `summary(for:)` (lines 296-303) needs `.forecastedHigh` added to the `.high` case in the comparator closure so it says "above" instead of falling through to the `default: "below"`. | Everything else in this file (`cgmHandledAlerts`, `enabledAlerts`, `disabledAlerts`, row rendering) iterates/filters generically on `.isReadingDriven` / `.isEnabled` / `.priority` — confirmed no other changes needed. `isReadingDriven == false` for `forecastedHigh` keeps it out of the CGM-handled section, correct per decision that CGM apps can't compute Trio's forecast. |
| `Trio/Sources/Modules/GlucoseAlerts/View/AddGlucoseAlertSheet.swift` | None | Confirmed: iterates `GlucoseAlertType.allCases` generically via `availableActiveOptions`, no per-type switch. |
| `Trio/Sources/Services/Alerts/AlertColdStartReplay.swift`, `TrioAlertManager.swift`, `TrioModalAlertScheduler.swift` | None | Confirmed via grep: these only test `GlucoseAlertType(slug:) != nil` or `== .urgentLow`, never an exhaustive switch over the type. No watch app or Live Activity file references `GlucoseAlertType` or `forecastedLow` at all (repo-wide grep). |
| `TrioTests/GlucoseAlertCoordinatorTests.swift` | `priorityOrder` test (lines 40-47) hardcodes exact indices (`urgentLow==0`, ..., `carbsRequired==4`) — **will break** once `forecastedHigh` shifts `carbsRequired` to index 5. `readingDrivenSetIsExact` (line 86-89) asserts the reading-driven set is exactly `{.high, .low, .urgentLow}` — stays correct since `forecastedHigh.isReadingDriven == false`. | Flagged for Phase 02, not touched in this phase per task 1's instruction ("note which assertions... will need updating in Phase 02"). |
| `TrioTests/GlucoseAlertTests.swift` | No hardcoded counts/orderings that break; `isReadingDriven` test (line 78-84) only asserts specific types, doesn't enumerate the false set exhaustively, stays valid. | No Phase 02 action needed beyond optionally adding forecastedHigh-specific cases. |
| `TrioTests/GlucoseAlertsStoreTests.swift` | Uses `GlucoseAlertType.allCases` and `.count` generically throughout (`freshSeedAllTypes`, `fullLoadNoDuplicates`, `freshSeedHasNoneAvailable`) — these adapt automatically and won't break. | No Phase 02 action needed. |
| `TrioTests/ForecastedGlucoseEvaluatorTests.swift` | All calls to `evaluate(determination:...)` omit `direction:`, so they keep exercising the `.low`/`min` path unchanged and continue to pass. | Phase 02 should add a parallel set of tests exercising `.high`/`max`. |
| `TrioTests/DeviceAlertsStoreTests.swift` | line 489 iterates `GlucoseAlertType.allCases` generically (unrelated device-alert store test, not glucose-alert-specific logic) | No changes needed. |

## Localized-string extraction check

Deferred to the build task (task 5) — the four new `String(localized:)` keys
extracted by `SWIFT_EMIT_LOC_STRINGS = YES` will be verified against
`Trio/Sources/Localizations/Main/Localizable.xcstrings` after the build.
