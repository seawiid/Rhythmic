# Next update — work list

Captured 2026-11-17 after PRs #4–#6 (wordmark/icon, departure-zone planning, no-shift trips, Xcode settings).
Pick items up in any order; the top three are the priority.

## Priority

### 1. Live trip + reminders
- [ ] Decide which trip is **live** automatically (now inside a plan's horizon, else the next upcoming one that needs a shift) instead of relying on the user tapping a trip.
- [ ] Queue local notifications for the live trip; re-queue when the itinerary refreshes or the live trip changes.
- [ ] Test notifications on a real device (permission flow, delivery while locked, reschedule after plan regenerates).
- [ ] App-layer tests for trip selection and reminder scheduling (only `RhythmicCore` has tests today).

### 2. Every day ends with sleep
- [ ] Some timeline days don't end with a sleep block. Each day should end with that night's sleep.
- Start in `Planner` (sleep generation per night) and `TimelineLayout` (how days are cut at local midnight). Likely cases: the last day of the horizon (plan ends at midnight, before that night's sleep), travel days where the overnight flight replaces sleep, and days where the clock zone changes mid-day.

### 3. Back-to-back trips
- [ ] Chained trips (e.g. SIN → ADD → EBB → ADD → WDH → SIN) are planned one at a time, each assuming you start fully adjusted. Carry the estimated body-clock offset from one trip into the next.

## Remove "home time zone"
Planning already follows the **departure airport's zone** (`Planner` uses `trip.originZoneID`, rules `2026.11.1`). What's left of "home":
- [ ] `SetupViews.swift` — "Home time zone" picker in preferences (`Preferences.homeZoneID`).
- [ ] `SetupViews.swift` — "Show home time in details" toggle (`showHomeTime`).
- [ ] `PlanView.swift` — "Home" rows in block and flight detail sheets.
- [ ] `Planner.makePlan` short-stay check matches a "return trip" by origin/destination; keep that working without a home zone.
- [ ] Decide: drop `homeZoneID` from `Preferences` entirely (migrate saved state), or keep it hidden for the short-stay rule only.

## Import and parsing
- [ ] **Overlapping bookings**: TR 442 (SIN → KUL) and FY 3129 (XSP → SZB) on 10 Jan 2027 overlap and land in "Needs your review". Likely a changed/duplicate TripIt booking; detect superseded bookings and keep the newer one.
- [ ] **Google Calendar**: end-to-end test (needs an OAuth client ID; currently "Not set up"). Real Google import is unvalidated.
- [ ] Background refresh of TripIt / Google so trips and reminders stay current without opening the app.

## UI clean-up
- [ ] Onboarding still shows the old plain "Rhythmic" title and moon icon; use `Wordmark` and the R° mark.
- [ ] General UI and parsing bugs found while using it on the phone (add specifics here as they come up).

## Planning gaps (known v1 limits)
- [ ] **Short stays** (< ~2 days) return "not supported". Plan a "stay on home time" version instead; the user takes many short regional trips.
- [ ] **Missed sleep**: plan doesn't adapt if a sleep block is skipped.

## Nice to have
- [ ] Lock-screen widget / Live Activity for the Now · Up next card (pairs with the live-trip work).
- [ ] TestFlight (needs the $99 developer account) to end the 7-day reinstall.
- [ ] Git-ignored `Signing.local.xcconfig` for Team ID and bundle ID so nobody edits `project.pbxproj` to build to a phone.
