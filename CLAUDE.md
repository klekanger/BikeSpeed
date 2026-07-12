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
Location permission can be pre-granted for testing with `xcrun simctl privacy booted grant location lekanger.BikeSpeed`, though this simulator/iOS version has been observed to still show the system prompt on each fresh launch regardless — not an app bug, just re-verify on a real device if in doubt. Use Xcode's Debug ▸ Simulate Location, or `xcrun simctl location booted start --gpx <file>`, to exercise speed/course/altitude changes without a real ride.

## Architecture

Model layer speaks pure SI units (meters, m/s, degrees, seconds) throughout; only the view layer converts to km/h-vs-mph via `Measurement<UnitSpeed>`/`Measurement<UnitLength>`, which also localizes unit abbreviations for free (e.g. "km/t" in Norwegian).

- **`Models/`** — `TripState` (idle/running/paused), `MeasurementSystem` (metric/imperial + conversion/formatting helpers), `CompassDirection` (8-point compass derived from a GPS course angle).
- **`Services/LocationManager.swift`** — wraps `CLLocationManager`/`CLLocationManagerDelegate`, publishing filtered speed, course, altitude, and coordinate. Speed/course/altitude are rejected or held at their last valid value when accuracy is poor (see the filtering constants at the top of the file) rather than accepted as noise. Emits accepted fixes via a `PassthroughSubject` for `TripManager` to consume — it does not itself gate on trip state, so the gauge/compass/position stay live even when idle.
- **`Services/TripManager.swift`** — owns the Start/Pause/Reset state machine and accumulates distance/average-speed from `LocationManager`'s accepted fixes. Elapsed active time is wall-clock based (correct across backgrounding). Has its own GPS-teleport and jitter-floor guards, independent of `LocationManager`'s filtering.
- **`Services/AddressLookupManager.swift`** — reverse-geocodes `LocationManager`'s accepted fixes into the street name shown on the direction cell's caption line. Subscribes to the same `PassthroughSubject` as `TripManager` and, like it, doesn't gate on trip state. Lookups are gated on distance moved *and* time since the last attempt, with exponential backoff on failure, because reverse geocoding is a network call and `CLGeocoder` throttles callers that ask too often — see the file before touching those constants. Uses `MKReverseGeocodingRequest` on iOS 26+ and `CLGeocoder` below; the two return different granularity, so the modern path trims the formatted address down to a bare street.
- **`Services/SettingsStore.swift`** — persists `maxGaugeSpeedKMH` (always canonical km/h regardless of display unit) and `measurementSystem` to `UserDefaults` directly (not `@AppStorage`, since `@AppStorage` inside a plain `ObservableObject` doesn't reliably trigger view updates — see the file for the manual `didSet` pattern used instead).
- **`Views/`** — `GaugeFaceView` (Canvas: dial/ticks/danger-arc, redrawn only when max speed changes) + `NeedleView` (a `Shape`, rotated every update) compose into `SpeedometerGaugeView`. The gauge sweeps 270° from -135° to +135° (12 o'clock = 0 speed midpoint convention documented inline); see `GaugeFaceView`'s angle-to-point math if adjusting tick layout. `DirectionIndicatorView` rotates directly by `CLLocation.course` (SwiftUI's rotation convention already matches course's clockwise-from-north convention, no axis flip needed).
- **`BikeSpeedApp.swift`** constructs `LocationManager` first, then `TripManager(locationManager:)` and `AddressLookupManager(locationManager:)` (order matters — both depend on location), and injects them plus `SettingsStore` as environment objects.

### Xcode project notes

- Targets iOS only (`SDKROOT = iphoneos`, `IPHONEOS_DEPLOYMENT_TARGET = 17.0`, `TARGETED_DEVICE_FAMILY = 1`). It was originally generated as a macOS app template and was retargeted by hand-editing `project.pbxproj` (no Xcode GUI in this environment) — if something looks like a leftover macOS setting, it's likely just not cleaned up yet.
- `GENERATE_INFOPLIST_FILE = YES` — there is no physical `Info.plist`; usage-description and other Info.plist keys live as `INFOPLIST_KEY_*` build settings in `project.pbxproj`, plus `InfoPlist.xcstrings` for the localized location usage description.
- Uses a `PBXFileSystemSynchronizedRootGroup` — new files dropped into `BikeSpeed/` are picked up automatically, no manual pbxproj edits needed for new Swift files (this applies to `.xcstrings` files too).
- `Localizable.xcstrings` holds all UI-facing strings (en + nb); compass abbreviations (N/NE/etc.) are intentionally not localized (identical in Norwegian).

Bundle identifier: `lekanger.BikeSpeed`. Swift 5.0, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
