# Flight import

All sources produce `ImportedSegment`s, which go through one normaliser (`ItineraryNormalizer`):
- **Updates:** the newest version of the same source event wins.
- **Duplicates across sources:** merged when the route matches, departures are within 3 h, and flight numbers are compatible. Conflicting times raise a review issue.
- **Cancellations:** removed from trips. A plan whose trip disappears is cleared, along with its reminders.
- **Airports:** time zones come from a bundled table of about 7,900 airports (generated from mwgg/Airports, MIT), with a small hand-checked list taking priority.
- **Past trips:** feeds include finished trips. Trips that ended more than a day ago, and their review items, are hidden (`NormalizationResult.upcoming`).
- **Missing fields, unknown airports, ambiguous or nonexistent DST local times:** reported for review and **never guessed**.
- **Grouping:** segments within 24 h of each other form one trip. A changed airport between legs is flagged as a ground transfer.

| Source | State | Notes |
|---|---|---|
| Manual entry | Working | Fallback. Local times per airport; zone from the bundled airport table or chosen by the user. |
| TripIt / any ICS feed | **Working with one real feed** | Read 23 flights correctly from a real TripIt feed (2026-11-17). Past trips are hidden. Not yet a test fixture. |
| Google Calendar (cloud API) | **Implemented, not connected** | Needs an OAuth client ID. Never shown as "connected" without one. |

## TripIt private feed
- The TripIt public API is closed to new developer integrations (checked 2026-11-16), so the feed is the practical path.
- In TripIt, enable the calendar feed and choose **all detailed plans**, not "just the trip title". A title-only feed is ignored by the parser (no route), so it produces nothing rather than wrong data.
- The feed URL is a secret. It's stored only in the iOS Keychain, and `webcal://` is converted to `https://`.
- Feed updates can lag and aren't live airline updates.
- **To validate:** export one real feed (redact it), add it as a test fixture, and check the SUMMARY/LOCATION/DTSTART formats against `ICSParser` and `FlightText`.

## Google Calendar
- Scopes requested:
  - `calendar.events.readonly`
  - `calendar.calendarlist.readonly` (so the user can pick calendars)
- `calendar.events.owned.readonly` is narrower, but it excludes subscribed calendars, such as a TripIt feed added to Google.
- OAuth grants access to every calendar at that scope. Choosing calendars only limits what Rhythmic reads, and the UI says so.
- Gmail-generated flights have `eventType = fromGmail`. They can be listed, read and watched. Their text isn't guaranteed to contain airports or flight numbers, so incomplete events are flagged for review.
- The event `timeZone` is a display zone, not an airport zone. The importer uses absolute instants from `dateTime` plus airport zones.
- Calendars visible in the iPhone Calendar app may be device calendars that the cloud API can't see.

### Enabling it
1. In Google Cloud Console, create a project, enable the **Google Calendar API**, and configure the OAuth consent screen (Testing mode, with yourself as a test user).
2. Create an **OAuth client ID** of type **iOS**, with bundle id = the app's bundle id.
3. In `App/Config/Info.plist`, set `GoogleClientID` to the client ID. Under `CFBundleURLTypes`, add a URL scheme equal to the reversed client ID (`com.googleusercontent.apps.…`).
4. Build, then use Itinerary → Google Calendar → Sign in → choose calendars → Import.

The OAuth/PKCE flow and the events.list paging have been compiled but **not run against a real account**.
