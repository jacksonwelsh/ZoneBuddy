# ZoneBuddy

An iOS app for riding Power Zone interval workouts on an FTMS-compatible stationary bike or trainer. Originally written to fill the gap left by Peloton's "Just Ride" mode.

SwiftUI + SwiftData, iOS 26, MVVM. Includes an Apple Watch companion that broadcasts heart rate to the phone over Bluetooth.

## What it does

- Build and edit structured interval workouts (per-interval power zone + duration).
- Connect to a bike or trainer over BLE using the FTMS protocol.
- Drive the workout: live timer, current/next interval, audio cues at zone changes.
- ERG mode (sets target watts on the trainer) and Free Ride.
- FTP ramp test.
- Workout history backed by SwiftData. CloudKit sync when available, local-only fallback otherwise.
- Writes cycling workouts to HealthKit.
- Plays Apple Music playlists during a ride (MusicKit).
- Share a workout as a universal link (`zonebuddy.jacksn.dev/workout/...`).
- App Intents for Siri / Shortcuts (start workout, query current/next interval).

## Watch app

- Streams heart rate from `HKWorkoutSession` to the iPhone/iPad over BLE (the phone advertises a custom GATT service; the watch connects as central).
- Mirrors the workout player UI so you can control playback from the wrist.

## Requirements

- Xcode 26+
- iOS 26.2+, watchOS 11+
- An FTMS-compatible bike or trainer for the bike features. Without one, use the "Sim Fakes" schemes.

## Building

The xcconfig files holding signing config aren't committed. To build:

1. Add `Debug.xcconfig` and `Release.xcconfig` under `ZoneBuddy/Config/`.
2. Change `DEVELOPMENT_TEAM` and the bundle identifiers in the project to your own.
3. If you want CloudKit sync and universal links to work, swap the iCloud container and associated domain in the entitlements files.

The "Sim Fakes" schemes (`ZoneBuddy (Sim Fakes)` and `ZoneBuddyWatch (Sim Fakes)`) wire in fake bike, trainer, and heart-rate providers so the app is usable in the simulator.

## Tests

Unit tests use Swift Testing. UI tests use XCTest.

```bash
xcodebuild test \
  -project ZoneBuddy.xcodeproj \
  -scheme ZoneBuddy \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1
```

The parallel-testing flags are there because parallel sims will OOM a 16GB machine.

## Layout

- `ZoneBuddy/` iOS app
- `ZoneBuddyWatch/` watchOS app
- `ZoneBuddyTests/` unit tests
- `ZoneBuddyUITests/` UI tests
