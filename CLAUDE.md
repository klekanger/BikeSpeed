# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

BikeSpeed is a fullscreen iPhone bike speedometer: an 80s-car-style analog gauge showing live GPS speed, plus average speed, distance, altitude, GPS position, and direction of travel, with Start/Pause/Reset trip controls and a Settings screen for max gauge speed and metric/imperial units. Portrait only, status bar/home-indicator hidden, screen-sleep disabled — designed to run mounted on a bike handlebar.

Localized in English and Norwegian (`nb`) via String Catalogs, following device language.

## Commands

Build from the command line (targets the iOS Simulator; the project has no macOS destination):
```
xcodebuild -project BikeSpeed.xcodeproj -scheme BikeSpeed -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
```

There is no test target yet. For iteration, prefer opening `BikeSpeed.xcodeproj` in Xcode and using Run/Preview.

To manually run in the simulator:
```
xcrun simctl boot "iPhone 17"   # if not already booted
xcrun simctl install booted <path-to>/BikeSpeed.app
xcrun simctl launch booted lekanger.BikeSpeed
```
Location permission can be pre-granted for testing with `xcrun simctl privacy booted grant location lekanger.BikeSpeed`, though this simulator/iOS version has been observed to still show the system prompt on each fresh launch regardless — not an app bug, just re-verify on a real device if in doubt.

To exercise speed/course/altitude without a real ride, use Xcode's Debug ▸ Simulate Location, or simulate a route from the command line:
```
xcrun simctl location booted start --speed=8 --interval=1 59.9139,10.7522 59.9184,10.7522
```
`--speed` is **m/s**, not km/h (8 m/s ≈ 29 km/h). Three things to know, each of which will otherwise look like an app bug:
- The process must outlive the shell that launched it, or fixes silently stop arriving and the app appears frozen (needle stuck, distance stuck at 0).
- `simctl location booted set <lat,lon>` is not a substitute for a route: a static point reports `CLLocation.speed` as the negative "unknown" sentinel, which `TripManager` deliberately ignores. To simulate a **standstill** (e.g. to trigger auto-pause) run a slow route instead — `--speed=0.2` between two points a few metres apart — which produces real near-zero speeds.
- Don't jump the position between routes while a trip is running. A multi-kilometre teleport is exactly what `TripManager`'s teleport guard is built to reject, so distance will legitimately refuse to count it. Start the route before tapping Start, and keep successive routes adjacent.

## Architecture

Model layer speaks pure SI units (meters, m/s, degrees, seconds) throughout; only the view layer converts to km/h-vs-mph via `Measurement<UnitSpeed>`/`Measurement<UnitLength>`, which also localizes unit abbreviations for free (e.g. "km/t" in Norwegian).

- **`Models/`** — `TripState` (idle/running/paused), `MeasurementSystem` (metric/imperial + conversion/formatting helpers), `CompassDirection` (8-point compass derived from a GPS course angle).
- **`Services/LocationManager.swift`** — wraps `CLLocationManager`/`CLLocationManagerDelegate`, publishing filtered speed, course, altitude, and coordinate. Fixes are filtered on two independent axes (see the constants at the top of the file): *accuracy* — speed/course/altitude are rejected or held at their last valid value rather than accepted as noise — and *age*, since `startUpdatingLocation()` replays the last cached fix, which can be minutes old yet perfectly accurate. Everything downstream treats an emitted fix's `timestamp` as "now", so both filters have to hold. Emits accepted fixes via a `PassthroughSubject` for `TripManager` to consume — it does not itself gate on trip state, so the gauge/compass/position stay live even when idle.
- **`Services/TripManager.swift`** — owns the Start/Pause/Reset state machine and accumulates distance/average-speed from `LocationManager`'s accepted fixes. Elapsed active time is wall-clock based (correct across backgrounding). Has its own GPS-teleport and jitter-floor guards, independent of `LocationManager`'s filtering. Also implements auto-pause (`isAutoPaused`), which freezes distance *and* the clock while the rider is stopped — the clock is the point, since average speed is distance ÷ active time and would otherwise sag at every red light. It's a flag on `.running` rather than a `TripState` case so a manual pause stays distinguishable (an auto-pause must not survive as one, and `canSaveTrip` must not light up mid-ride); the pause/resume thresholds are deliberately different (hysteresis) because GPS speed drifts at a standstill.
- **`Services/AddressLookupManager.swift`** — reverse-geocodes `LocationManager`'s accepted fixes into the street name shown on the direction cell's caption line. Subscribes to the same `PassthroughSubject` as `TripManager` and, like it, doesn't gate on trip state. Lookups are gated on distance moved *and* time since the last attempt, with exponential backoff on failure, because reverse geocoding is a network call and `CLGeocoder` throttles callers that ask too often — see the file before touching those constants. Uses `MKReverseGeocodingRequest` on iOS 26+ and `CLGeocoder` below; the two return different granularity, so the modern path trims the formatted address down to a bare street.
- **`Services/SettingsStore.swift`** — persists `maxGaugeSpeedKMH` (always canonical km/h regardless of display unit), `measurementSystem`, `appLanguage` and `autoPauseEnabled` to `UserDefaults` directly (not `@AppStorage`, since `@AppStorage` inside a plain `ObservableObject` doesn't reliably trigger view updates — see the file for the manual `didSet` pattern used instead).
- **`Views/`** — `GaugeFaceView` (Canvas: dial/ticks/danger-arc, redrawn only when max speed changes) + `NeedleView` (a `Shape`, rotated every update) compose into `SpeedometerGaugeView`. The gauge sweeps 270° from -135° to +135° (12 o'clock = 0 speed midpoint convention documented inline); see `GaugeFaceView`'s angle-to-point math if adjusting tick layout. `DirectionIndicatorView` rotates directly by `CLLocation.course` (SwiftUI's rotation convention already matches course's clockwise-from-north convention, no axis flip needed).
- **`BikeSpeedApp.swift`** constructs `LocationManager` and `SettingsStore` first, then `TripManager(locationManager:settings:)` and `AddressLookupManager(locationManager:)` (order matters — both depend on location, and `TripManager` also needs settings for the auto-pause toggle), and injects them all as environment objects.

### Xcode project notes

- Targets iOS only (`SDKROOT = iphoneos`, `IPHONEOS_DEPLOYMENT_TARGET = 17.0`, `TARGETED_DEVICE_FAMILY = 1`). It was originally generated as a macOS app template and was retargeted by hand-editing `project.pbxproj` (no Xcode GUI in this environment) — if something looks like a leftover macOS setting, it's likely just not cleaned up yet.
- `GENERATE_INFOPLIST_FILE = YES` — there is no physical `Info.plist`; usage-description and other Info.plist keys live as `INFOPLIST_KEY_*` build settings in `project.pbxproj`, plus `InfoPlist.xcstrings` for the localized location usage description.
- Uses a `PBXFileSystemSynchronizedRootGroup` — new files dropped into `BikeSpeed/` are picked up automatically, no manual pbxproj edits needed for new Swift files (this applies to `.xcstrings` files too).
- `Localizable.xcstrings` holds all UI-facing strings (en + nb), keyed by the English source string. Compass abbreviations are localized too (Norwegian swaps the east/west axis: Ø/V for E/W), keyed as "N"/"NE"/… — note these single-letter keys mean a bare `Text("N")` anywhere would now get translated.
- Strings that are resolved to a `String` in code (rather than handed to SwiftUI as a `LocalizedStringKey`) must go through `AppLanguage.localizedString(forKey:)`, not `String(localized:)` — the latter ignores the in-app Language override and follows the device language instead. See `AppLanguage` for why.

Bundle identifier: `lekanger.BikeSpeed`. Swift 5.0, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
