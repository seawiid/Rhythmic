# Product & architecture plan

## Goal
A personal iPhone app that imports flights and gives **one clear, research-informed timeline** for jet lag:
- sleep and wake times
- bright light (prioritise / helpful / reduce)
- optional naps
- caffeine (permitted / stop)
- wind-down
- concise reminders

Scientific detail sits behind an optional "Why?". It's general guidance: not a diagnostic tool, not a body-clock measurement, and not a validated treatment.

## Decisions
| Decision | Choice | Why / reversible? |
|---|---|---|
| Platform | iPhone only (SwiftUI, iOS 17+) | Confirmed by user 2026-11-16. Local notifications work offline; a web app couldn't schedule them reliably. The engine is a pure Swift package, so porting it to Android would mean a rewrite but not a redesign. |
| Backend | None | The plan is computed on device and stored locally (JSON in Application Support). Secrets live in the Keychain. |
| Planner | Deterministic rule engine, versioned (`RuleBook.version`) | Same inputs + rule version = same plan. No runtime LLM. |
| App name / bundle id | "Rhythmic" (repo name) / `com.example.rhythmic` | Placeholders; change in Xcode before installing on a device. |
| Demo horizon | 2 days before departure → 2 days after arrival | A banner states the estimated remaining misalignment, so the plan never implies full recovery. |
| Missed-sleep adjustment | Not built (v1) | Per brief. Itinerary changes *do* regenerate the plan. |
| Melatonin, live delays, logging, wearables | Not built | Per brief. |
| Licence | GPL-3.0 (from repo) | Note for any future App Store distribution. |

## Architecture
```
RhythmicCore/            Swift package. Pure Foundation, no UI. Tested with `swift test`.
  Models/                Time (IANA zones, DST-safe LocalDateTime), Itinerary, Preferences, Plan
  Itinerary/             Normalizer (dedupe, updates, cancellations, grouping), Importers
                         (ICS + Google event parsers), Airports (IATA → zone + coords), Fixtures
  Planning/              Planner (rules), RuleBook (evidence metadata + parameters), Solar
  Notifications/         NotificationPlanner (transitions → reminders), NotificationSync (diff)
  rhythmic-cli           Dev tool: prints a plan in local + home time
App/                     Xcode project (iOS). Thin layer over the core.
  Services/              Store (JSON + Keychain), NotificationScheduler, ICS/Google importers
  Views/                 Plan (Now card, timeline, Why? sheets), setup (preferences, itinerary)
```
The concerns are separate, as the brief asked: **import/normalise → preferences → rules → render → notify**. Each piece is testable in isolation.

## Planning algorithm (summary)
1. Zone difference Δ = destination − home offset at arrival, normalised to (−12, 12]. Pick the direction (S1).
2. Phase model: the estimated body clock moves with the pre-travel sleep shift, holds during travel, then moves at population-average rates (C1, C2, P1).
3. Sleep:
   - Preparation nights at shifted home times.
   - Destination nights step toward local time (Z1).
   - Travel sleep only where feasible (usable flight time or a long layover). With the daytime-flight preference, only during the biological night (Z2, Z3).
4. Light windows relative to the estimated Tmin, with priority-based overlap resolution, split at sunrise/sunset (L1–L3).
5. Naps on unusually long days only (N1). Caffeine windows per waking period (K1–K3).
6. Notifications at transitions only, merged within 15 min, nothing during sleep, durations used in flight (phone zone unreliable).

## Notification behaviour (iOS)
- `UNTimeIntervalNotificationTrigger` (absolute instants), so a phone time-zone change doesn't shift reminders.
- The next 60 are scheduled (iOS cap: 64 pending per app) and topped up whenever the app becomes active.
- Every id is prefixed `rhythmic.<planID>.`. On any plan change, disable, or plan end, all stale ones are removed (`NotificationSync`).
- Not alarms: Silent mode, Focus and notification settings can suppress them, and the UI says so. No Critical Alerts entitlement.
- Scheduled reminders fire offline. A trip with more than ~60 reminders needs the app opened at least once mid-trip to schedule the rest (not reached by the demo plan, about 24 reminders).

## Status of the first vertical slice
See README "Status".

## Next steps
1. Validate import with a **real** TripIt feed and real Google `fromGmail` events, then adjust the parsers.
2. Create a Google Cloud OAuth client to enable the Google import (see IMPORT.md).
3. Specialist review of the *Proposed default* rules in EVIDENCE.md.
4. On-device test of notification delivery across a real time-zone change.
5. Optional: background refresh (BGAppRefreshTask) to re-fetch itinerary sources and top up reminders.
