# Evidence → rules (rule version `rules-2026.11.0`)

Source of truth in code: `RhythmicCore/Sources/RhythmicCore/Planning/RuleBook.swift` (text + metadata) and `RuleParameters` (numbers). Changing any number requires bumping `RuleBook.version`. Every plan stores the rule version it was generated with.

**Reviewed:** 2026-11-16. The source claims were re-checked against the live pages on that date (summary below).
**Status:** engineering-validated only. **No clinical validation and no specialist review yet.** All rules marked *Proposed default* need review by a sleep or circadian specialist before anyone outside the project relies on them.

## Basis legend
- **Source-supported**: the rule follows directly from cited guidance or research. It's still general guidance, not an individual prediction.
- **Proposed default**: a product choice inside the range the sources discuss. Needs review.
- **Heuristic**: an engineering simplification needed to produce a schedule at all. Not a scientific claim.

## Rules

| ID | Rule (what the engine does) | Basis | Sources / evidence | Key assumptions |
|---|---|---|---|---|
| S1 | Direction: advance east, delay west. For eastward changes, pick the direction with fewer estimated days (advance at 1 h/day vs delay at 1.5 h/day). Crossover ≈ 9.6 h, so ≥ 10 h east → delay. | Proposed default | CDC Yellow Book (rates); circadian travel review (PMC2829880) | Geography alone isn't a validated rule. Shifts ≥ 10 h show an "uncertain" warning. |
| S2 | Trips < 2 days: refuse to plan, and say that CDC suggests staying on home time. Changes < 2 h: follow local time, no circadian light windows. | Source-supported (CDC "< 2 days"); the 2 h threshold is proposed | CDC Yellow Book | Needs the return flight imported to detect a short stay. |
| C1 | Estimated body-clock minimum (Tmin) = habitual wake − 3 h. | Heuristic | CDC: "approximately 2–4 hours prior to habitual wake time" | Not a measurement. Worse with irregular sleep, recent travel, or alarms. |
| C2 | After arrival, the estimated clock moves 1 h/day (advance) or 1.5 h/day (delay). No movement is assumed during travel. | Source-supported (population averages) | CDC Yellow Book | Used only to position windows and the end-of-plan residual. Never shown as a prediction. |
| P1 | Preparation days (2): sleep moves 30 min/day (default "gentle") or 60 min/day, same duration. The model assumes the clock follows. | Source-supported (CDC 1 h/day for 2–3 days); 30 min default is proposed | CDC; Eastman et al. 2005 (2 h/day ≈ 1 h/day advance [1.8 vs 1.5 h, n.s.], worse sleep-log measures) | Moving bedtime ≠ the clock moving equally. Eastman used ~5000 lux intermittent morning light, which our users won't reproduce. |
| L1 | Advance: reduce light [Tmin−4 h, Tmin), prioritise [Tmin, Tmin+5 h), helpful [Tmin+5 h, Tmin+8 h). Delay: mirrored. Overlaps resolve as sleep > circadian reduce > prioritise > wind-down > helpful. | Principle source-supported; window widths proposed | CDC; Serkh & Forger 2014 (model; doesn't validate our app); PMC2829880 | CDC phrases this as morning vs evening light, not "before/after Tmin". The Tmin framing comes from the review and model literature. |
| L2 | Says "daylight" when the sun is up at the airport location (NOAA approximation), otherwise "bright indoor light". 30–60 min suggested, as a duration inside the window. A screen is never presented as equivalent. Never look at the sun; no sunglasses while driving. | Proposed default | CDC; Eastman 2005 protocol | 30–60 min isn't an established equivalent dose across weather and conditions. |
| L3 | Dim light in the hour before main sleep (yields to circadian "prioritise" windows). | Proposed default | General sleep guidance (CDC) | — |
| Z1 | Destination nights keep habitual duration. Bedtime = local habitual bedtime shifted toward the body clock by max(0, residual − 2 h advance / 3 h delay), in 15 min steps. | Proposed default | CDC (protect sleep), PMC2829880 | The allowance values are product choices. |
| Z2 | With "I rarely sleep on daytime flights", main sleep on a flight is only planned during the biological night (body-clock sleep window −1 h / +2 h). Without it, destination-night sleep on flights is also allowed. | Heuristic (user preference) | — | Usable flight time excludes the first 30 min and the last 45 min. |
| Z3 | Ground sleep ends ≥ 3 h before departure. The first hour after landing stays free. | Heuristic | — | — |
| N1 | Optional nap *window* (≤ 3 h, late in the allowed range, ending ≥ 5 h before main sleep) when the awake span ≥ max(16 h, usual waking day + 1.5 h). Suggested 20–30 min. | Source-supported (20–30 min); thresholds proposed | CDC | Optional. Never notified. |
| K1 | Caffeine permitted (users only) until 8 h before main sleep (10 h if sensitive), then "avoid". | Proposed default | CDC (sample schedule: stop 6 h before bed); Gardiner 2025 (n = 23 young men; 400 mg disrupted sleep even at 12 h; 100 mg showed no significant effect at 4 h); FDA (400 mg/day reference, not a target) | 8 h is more conservative than CDC's example and isn't a universal threshold. Dose matters but isn't tracked. Non-users are never told to start. |
| K2 | No caffeine in the hour before an optional nap window. | Proposed default | — | — |
| K3 | Context: evening caffeine delayed circadian timing in a small study, so there's no evening caffeine. No "minutes shifted per cup" is modelled. | Source-supported | Burke 2015 (n = 5; ~200 mg 3 h before bed → ~40 min delay) | — |

## Explicitly deferred
- **Melatonin:** dosing and timing differ for sleep-promoting vs phase-shifting effects. Contraindications and product quality need a separate review. The 2002 Cochrane review is old. Not in v1.
- **Missed-sleep adaptation, sleep logging, wearables.**
- **Short-stay "stay on home time" plans** (refused with an explanation instead).

## Source check (2026-11-16)
- **CDC Yellow Book, jet lag:**
  - Nadir "approximately 2–4 hours prior to habitual wake time".
  - Adaptation 1.5 h/day west, 1 h/day east.
  - Shift sleep 1 h/day for 2–3 days before travel.
  - Trips < 2 days: avoid adapting.
  - Naps 20–30 min.
  - Caffeine: example cutoff 6 h before bed.
- **Eastman 2005:** 2 h/day vs 1 h/day gave 1.8 vs 1.5 h phase advance (not significant). Sleep-log measures were worse at 2 h/day; actigraphy showed no difference.
- **Gardiner 2025:** n = 23 healthy young men. 400 mg at 12 h: sleep onset +15 min, deep sleep −21 min. 100 mg showed no significant effect at any timing.
- **Burke 2015:** n = 5. About a double espresso 3 h before bed delayed melatonin onset by ~40 min.
- **FDA:** 400 mg/day "not generally associated with negative effects" for most healthy adults. Sensitivity varies.
