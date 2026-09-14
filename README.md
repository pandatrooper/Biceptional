# Biceptional

A personal WHOOP-style companion for Apple Health. Native SwiftUI, iOS 27+, data stays on device.

Biceptional reads HRV, resting heart rate, sleep, workouts, weight, and nutrition from HealthKit, then computes **Recovery**, **Sleep**, and **Strain** against *your* rolling baseline — not population norms. Workouts, body weight, and meals you log are written back to Health so other apps can use them.

This is a personal-use Xcode project, not an App Store submission. Correctness, local ownership, and offline behavior come first.

## Open in Xcode

Requires **Xcode 26+** (iOS 27 / watchOS 27 SDK) and a physical iPhone. HealthKit is extremely limited in the Simulator.

1. Open `Biceptional.xcodeproj`.
2. Select the **Biceptional** target → **Signing & Capabilities**.
3. Choose your **Team**. The bundle ID is `com.pandatrooper.Biceptional` — change it if that ID is not yours.
4. Complete the capability checklist below. Entitlements and usage strings are already in the repo, but Xcode still has to associate them with your signing team.
5. Run on a device that has Apple Health data (ideally paired with an Apple Watch).

## Xcode setup that cannot be done from code

These are already represented in the project files. Confirm they survive signing and that your team is allowed to use them.

### 1. HealthKit capability (iOS app)

Target **Biceptional** → Signing & Capabilities → **+ Capability** → **HealthKit**.

Check:

- **Background Delivery** — required for `HKObserverQuery` to wake the app when new samples land. This entitlement is `com.apple.developer.healthkit.background-delivery` and is already in `Biceptional/Biceptional.entitlements`. A paid Apple Developer Program team is typically required; a free personal team may refuse it. Foreground refresh still works without it.

Do **not** enable Clinical Health Records.

### 2. App Groups (iOS app + widget)

Add **App Groups** to both **Biceptional** and **BiceptionalWidgets**:

```
group.com.pandatrooper.Biceptional
```

This group is how today's Recovery / Sleep / Strain payload reaches WidgetKit. The identifier is hardcoded in `Biceptional/Utilities/AppGroup.swift` and `BiceptionalWidgets/TodaySnapshotPayload.swift`.

### 3. Background Modes (iOS app)

Signing & Capabilities → **Background Modes**:

- Background fetch
- Background processing

`UIBackgroundModes` and `BGTaskSchedulerPermittedIdentifiers` (`com.pandatrooper.Biceptional.refreshScores`) are already in `Biceptional/Info.plist`. HealthKit observer queries are the primary refresh path; the BGTask is a backup scheduler.

### 4. Info.plist usage descriptions

Already present in `Biceptional/Info.plist` **and** duplicated as `INFOPLIST_KEY_NSHealthShareUsageDescription` / `INFOPLIST_KEY_NSHealthUpdateUsageDescription` in the target build settings so they survive Info.plist regeneration:

| Key | Why |
| --- | --- |
| `NSHealthShareUsageDescription` | Read HRV, HR, sleep, energy, workouts, weight, VO₂ max, dietary macros |
| `NSHealthUpdateUsageDescription` | Write workouts, body mass, dietary energy/macros |

Watch target has the same two keys in `BiceptionalWatch/Info.plist`.

### 5. Watch app

Target **BiceptionalWatch**:

- HealthKit capability
- Bundle ID `com.pandatrooper.Biceptional.watchkitapp`
- `WKCompanionAppBundleIdentifier` = `com.pandatrooper.Biceptional`

Live `HKWorkoutSession` / `HKLiveWorkoutBuilder` only run on watchOS. The iPhone app logs strength/cardio manually and **auto-imports** `HKWorkout` samples written by Apple Watch or other apps so nothing is double-logged.

### 6. Widget extension

Target **BiceptionalWidgets**, bundle ID `com.pandatrooper.Biceptional.widgets`. Home Screen (systemSmall / systemMedium) and Lock Screen (circular / inline / rectangular) families show today's Recovery and Sleep.

## Architecture

```
Biceptional/
  BiceptionalApp.swift          Scene, SwiftData container, HealthKit observers
  ContentView.swift             TabView + first-launch Health authorization
  Models/                       SwiftData (@Model) + score value types
  ViewModels/                   @Observable models for each tab
  Views/                        Dashboard first, then Recovery/Sleep/Workouts/Weight/Nutrition/Trends/Settings
  Services/HealthKitManager.swift
  Services/ScoringEngine.swift  Recovery / Sleep / Strain math (formulas commented inline)
  Services/ScoreRefreshService.swift
BiceptionalWidgets/             WidgetKit
BiceptionalWatch/               Start/end workout + live HR/strain
BiceptionalTests/               ScoringEngine unit tests
```

MVVM, SwiftUI-only except where HealthKit, haptics (`UINotificationFeedbackGenerator`), or workout session APIs require a UIKit/WatchKit type.

**Persistence:** SwiftData for computed daily snapshots, workout logs (including strength sets / supersets), weight samples, food entries, custom foods, and editable phase targets.

**Ingestion:** `HealthKitManager` requests read/write, runs `HKObserverQuery` + `HKAnchoredObjectQuery`, and enables hourly background delivery. `ScoreRefreshService` recomputes scores, imports new workouts/weight, and writes `TodaySnapshotPayload` into the App Group.

## Scores (approximations, not WHOOP)

WHOOP's formulas are proprietary. Ours are documented in `Services/ScoringEngine.swift`. Summary:

**Recovery (0–100)** — z-scores vs. a 30-day personal baseline.

| Input | Default weight | Direction |
| --- | --- | --- |
| Overnight HRV (SDNN) | 40% | higher than baseline → better |
| Resting HR | 30% | lower than baseline → better |
| Sleep score | 25% | already 0–100 |
| Respiratory rate | 5% | lower than baseline → better |

`component = clamp(50 + 15z, 0, 100)`. Missing signals are dropped and remaining weights renormalized. The Recovery screen shows each input's weight, raw value, baseline, and z-score.

HealthKit exposes SDNN, not WHOOP's overnight RMSSD. That limitation is called out in the Recovery UI copy and in `HealthKitManager`.

**Sleep (0–100)** — duration vs. an editable 7.5–8.5h window (50%), 7-day bed/wake consistency (25%), stage mix when the source provides Core/Deep/REM (25%). Without staging, duration/consistency renormalize to 67/33. Hypnogram is a Swift Chart.

**Strain (0–21)** — WHOOP-style saturating scale from HR-zone minutes plus active energy, relative to a rolling personal-max load:

```
load   = 1·z1 + 2·z2 + 3·z3 + 5·z4 + 8·z5 + kcal/50
strain = 21 × (1 − exp(−load / τ))    τ = personalMax / 3
```

Max HR for zones is Tanaka `208 − 0.7 × age` (age is a Settings field).

**Weight** — 7-day rolling average is the dashboard number. Raw daily points are a faint chart series. Status is `On track` / `Flat` / `Losing fast` / `Gaining fast` from the slope of that average vs. an editable kg/week target.

**Nutrition defaults** (Settings, not hardcoded): 2,400 kcal, 160 g protein. Custom foods are the primary path (vegetarian Indian home cooking, log by serving or grams). If another app already wrote dietary samples to Health for today, Nutrition offers those totals instead of duplicating entry.

## First launch

The app requests HealthKit authorization, then:

1. Pulls overnight physiology and last night's sleep.
2. Imports existing `HKWorkout` and body-mass samples.
3. Computes today's scores and stores a `DailySnapshot`.
4. Schedules local notifications (morning Recovery, weight, food) if enabled.

Grant **all** requested read types or Recovery will sit on limited data (the UI says so). HealthKit does not tell the app which read types were denied.

## Tests

Product → Test (or `Cmd-U`) runs `BiceptionalTests`, which cover Recovery renormalization, Sleep duration scoring, Strain bounds, weight-status rules, and Pearson correlation.

There is no iOS Simulator HealthKit fixture in this repo. Scores on Simulator will be empty unless you skip Health and browse the UI.

## Privacy

No accounts, no network API, no analytics. Computed state lives in the on-device SwiftData store. CSV export is a share sheet for a date range you pick.
