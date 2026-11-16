# Rhythmic

Circadian rhythm and jet-lag planning app for iPhone. It imports your flights and gives one clear, research-informed timeline: sleep, bright light, light reduction, optional naps, caffeine and wind-down, with concise reminders while the plan is active.

> Rhythmic offers research-informed suggestions based on your itinerary and usual sleep habits. It does not measure your body clock, provide medical advice, or guarantee results.

## Docs
- [docs/PLAN.md](docs/PLAN.md): product decisions and architecture
- [docs/EVIDENCE.md](docs/EVIDENCE.md): every scheduling rule with source, basis, assumptions and review date
- [docs/IMPORT.md](docs/IMPORT.md): Google Calendar and TripIt feed import, plus setup

## Layout
- `RhythmicCore/`: Swift package with the scheduling engine, itinerary normalisation, notification planning and tests
- `App/`: SwiftUI iOS app (`App/Rhythmic.xcodeproj`)

## Build & test
Requires Xcode 16+ selected as the developer directory (`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`).

```bash
cd RhythmicCore && swift test             # engine tests
swift run rhythmic-cli east               # print the demo plan (also: west, --flights-ok)
open ../App/Rhythmic.xcodeproj            # run on a simulator or iPhone
```
Before installing on a device, change the bundle id (`com.example.rhythmic`) and pick your signing team in Xcode.

Debug builds accept `-RhythmicPreview 2026-11-23T14:00:00Z` as a launch argument to open the demo plan at a given moment.

## Status (v0.1, 2026-11-16)
**Works**
- Preferences → deterministic plan → timeline → local notification scheduling, using the sample Windhoek → Addis → Singapore trip and manual flight entry.
- The "rarely sleep on afternoon flights" preference is applied before planning.
- Plans regenerate on itinerary or preference changes. Stale reminders are replaced; reminders stop at plan end or when disabled.
- Offline: the plan is stored locally and reminders are scheduled with iOS.

**Tested**
- 43 engine tests (Swift Testing). They cover the brief's time conversions, the westward 10:00 arrival, DST fall-back, fractional offsets, the date line, invariants across 9 scenarios, import dedupe/update/cancel/missing fields, and notification merging and staleness.
- App builds and renders in the iOS Simulator (checked by screenshot).

**Mocked / unvalidated**
- The sample itinerary is fixture data.
- ICS (TripIt) and Google event parsers were tested only on synthetic samples.
- Google OAuth hasn't been run (needs a client ID).
- Notification delivery hasn't been observed on a device.

**Needs specialist review**
- All rules marked *Proposed default* in EVIDENCE.md.
- This is engineering validation only; nothing here is clinical validation.

## Licence
GPL-3.0 (see LICENSE).
