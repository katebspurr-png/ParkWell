# ParkWell Architecture

For product context and scope, read [HANDOFF.md](HANDOFF.md) first. This doc
describes how the Phase 1 code is put together.

## The core loop

Everything serves one pipeline, running continuously while driving:

```
CLLocation update
   │  LocationService (high accuracy inside zones B/C/H, SLC outside)
   ▼
SegmentMatcher          nearest block face within 30 m, or nil
   ▼
RuleEngine              segment + dynamic overlays + "now" → Verdict
   │                    (pure function — no I/O, fully unit-tested)
   ├──▶ LiveActivityController   Dynamic Island / Lock Screen color state
   ├──▶ AudioCueService          tone/spoken cue, only when the state CHANGES
   └──▶ ContentView              in-app status card
```

`AppModel` wires it together. The key product behavior lives in one condition:
cues fire only on a *state transition* (new headline or level), so driving
down a block with one rule is silent, and crossing into a loading zone speaks
up exactly once, at the moment it matters.

## Verdict semantics

| Level | Meaning | Examples |
|---|---|---|
| `green` | Legal, park now | free street, paid zone outside paid hours |
| `yellow` | Legal with a condition | paid hours active, time limit, loading zone |
| `red` | Do not park | no-stopping, permit-only, accessible, winter ban, street cleaning |
| `unknown` | We honestly don't know | unmapped street, unreadable sign |

Priority order in `RuleEngine`: winter ban → street cleaning → no-stopping →
accessible → permit-only → loading zone → paid → time-limited → free. Dynamic
overlays always beat static rules.

**Staleness is a first-class output.** If the overlay snapshot is missing or
older than 6 hours, every verdict carries `isStale = true`, and each surface
(Live Activity, spoken cue, main screen) tells the user rather than showing a
confident color on stale data. The Live Activity also sets a 2-minute
`staleDate` so iOS itself dims the surface if updates stop (tunnel, GPS loss).

## Two-layer data model

Mirrors the handoff doc's split, and it's load-bearing in the schema:

- **Static layer** (`street_segments`, `segment_rules`): hand-mapped, changes
  rarely. Rules carry time windows with optional `effective_from/until` dates
  so schedule changes (e.g. Saturday paid hours starting 2026-07-18) ship in
  data *before* the changeover — no app update, no flag day.
- **Dynamic overlay** (`winter_ban_status`, `street_cleaning`): the genuinely
  hard part. The `hrm-alerts` edge function polls HRM's winter-operations
  pages on a schedule and flips the ban flag; when it can't get a confident
  read it writes nothing, and clients degrade to "stale" rather than wrong.

Everything is keyed by city from day one (`cities`, `zones`) so city #2 is a
dataset, not a migration.

## Client ↔ backend

The app talks to Supabase over plain PostgREST + edge-function HTTP:

- `RulesRepository` fetches segments+rules and the overlay tables, caches the
  snapshot to disk (with its `fetchedAt`, so staleness survives restarts),
  and refreshes the overlay every 15 minutes while running.
- `SignVisionService` posts a downscaled photo to the `interpret-sign` edge
  function; the Anthropic key lives only in the function's secrets.
- All tables are RLS read-only for the anon key; writes go through the
  service-role key (edge functions / data entry).

## Battery

`LocationService` runs `kCLLocationAccuracyBestForNavigation` only inside a
bounding box around the mapped zones; outside it drops to significant-
location-change monitoring and re-arms when the driver re-enters. The Live
Activity is updated locally by the running app (no push channel needed in
Phase 1). Real-world battery measurement is an open item — see handoff §10.

## Phase 2 posture

The Live Activity is deliberately the same architectural surface Apple is
bridging into CarPlay, and the audio-first interaction (no phone touches
while driving) matches the CarPlay Parking-category rules. Apply for the
CarPlay entitlement as soon as Phase 1 validates — it has review lead time.

## Data sources (updated after HRM open-data discovery)

The handoff doc assumed no public GIS existed — wrong, happily. HRM's open
data org (`data-hrm.hub.arcgis.com`) publishes queryable feature services,
imported by `tools/hrm-import/import_hrm.py` into rows tagged
`source = 'hrm_arcgis'` (re-imports replace only their own rows; hand-mapped
`source = 'manual'` data is never touched):

| Layer | Import target |
|---|---|
| Parking Pay Zones (A–J polygons) | `zones.boundary` |
| Commuter Permit Parking Streets (321 lines) | segments + `permit_only` rules |
| Accessible Parking Spots (306 points) | ~20 m stub segments + `accessible` rules |
| Winter ban Zone 1 / Zone 2 polygons | `winter_ban_zones` |
| Parking Pay Stations (176 points) | `tools/hrm-import/pay_stations.geojson` (mapping aid) |

What the open data does **not** provide: time windows/paid hours (policy,
encoded by us), per-block time limits and loading zones (still needs the
sign walk), and a live winter-ban on/off flag (still the scraper's job —
though the zone polygons now let us scope a declared ban to the right area).

### Mapping conventions (Halifax)

- **Loading zones default to 8 am–6 pm** unless the sign says 24H — outside
  posted hours they're ordinary legal parking. Only an explicitly 24H sign
  maps to an empty (= always active) windows array.
- Paid zones: weekdays 8 am–6 pm; Saturdays 8 am–6 pm from 2026-07-18
  (shipped as an `effective_from` window, already in the seed).
- Imported permit-street rules have **unverified hours** (flagged in their
  notes) — the verification walk should confirm posted windows.

## What's scaffolded vs. real

- ✅ Rule engine + tests, segment matching, audio ducking, Live Activity,
  camera fallback, schema, scraper skeleton, sign-mapper tool.
- ⚠️ `supabase/seed.sql` is **sample geometry** — replace with the real
  zone B/C/H walk data.
- ⚠️ `hrm-alerts` phrase patterns need verification against HRM's live pages.
- ⚠️ `Config.swift` needs your Supabase project URL + anon key.
- ❌ Not built yet: onboarding/permission flow polish, TestFlight setup,
  battery profiling, App Store privacy manifest.
