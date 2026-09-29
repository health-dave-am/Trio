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

**Result (2026-09-29): extraction did NOT happen.** After a full
`build-for-testing` run (see `Build verification` below), none of the four
new keys appear in `Trio/Sources/Localizations/Main/Localizable.xcstrings`:

- "High Glucose Soon" — not found
- "Fires when glucose is forecasted to be high within the next 20 minutes." — not found
- "Fires when the forecast at +20 minutes (blended across all available prediction curves) is at or above this value." — not found
- "Your glucose may go above %2$@ in %1$d min." — not found

`SWIFT_EMIT_LOC_STRINGS = YES` is confirmed set on the relevant targets in
`Trio.xcodeproj/project.pbxproj`, so the setting is not the problem — the
`.stringsdata` merge into the checked-in `.xcstrings` catalog apparently
requires a different build path than `xcodebuild build-for-testing`
(e.g. an Xcode-driven "Build" or an explicit localization export step) and
did not occur here. Per task 1's own instruction, this is left for Phase 02
to add the four keys to the catalog directly rather than relying on
automatic extraction.

## Build verification (task 5, 2026-09-29)

- Two submodules under the workspace were **not initialized** in this
  checkout: `LibreCRKit`, `LoopAlgorithm` (missing `Package.swift`, broke
  package resolution), plus `AccuChekKit`, `EversenseKit`, `LibreLoop`
  (missing `Package.swift`/build files, broke module resolution for
  `LibreLoop` specifically, referenced by `HomeStateModel.swift`). Ran
  `git submodule update --init` for all five — this is a local environment
  fix (checks out the already-pinned commit recorded in the superproject),
  not a code change, and does not appear in `git status` for the main repo.
- Picked `iPhone 16` (OS 18.5, id `824CA0D3-092A-47CA-B97E-790C1AA3B9C8`)
  since multiple same-name simulators exist across OS versions and the bare
  `name:` destination was ambiguous.
- `xcodebuild build-for-testing -workspace Trio.xcworkspace -scheme "Trio Tests" ...`
  **succeeded** (exit code 0, `TrioTests.xctest` built and embedded in
  `Trio.app/PlugIns/`). Only warnings remain (pre-existing Sendable/async
  warnings across LoopKit/LibreLoop, a few `var` never mutated in test
  files, a duplicate-build-file warning for `CalibrationsTests.swift`, and
  an `AccuChekKit` umbrella-header module-map warning) — none related to
  the `forecastedHigh` change.
- The project's own "Swiftformat" run-script build phase (runs on every
  build, confirmed in the build log) reformatted the two in-scope files
  changed in the previous task — `GlucoseAlertCoordinator.swift` and
  `GlucoseAlertsRootView.swift` — reordering the `.forecastedHigh`/`.high`
  case labels alphabetically. This is expected project-style enforcement,
  left in place. It also reformatted four unrelated test files inside the
  `EversenseKit` submodule as a side effect of building the whole
  workspace; those were **reverted** (`git checkout --` inside the
  submodule) since they are out of scope for this task.
- `git status` / `git diff --stat` now show exactly: the two in-scope
  Swift files (swiftformat-reordered case labels only, no logic change)
  and the two pre-existing Xcode scheme edits noted at the start of the
  session. No string-catalog changes (see extraction check above). Per
  task instructions, nothing was committed — left for the user to review
  and test on device.
