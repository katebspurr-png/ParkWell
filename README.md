# ParkWell

**Can I park here, right now?** — answered in the two seconds you have while
passing an open spot, for downtown Halifax + Dartmouth (paid zones B, C, H).

ParkWell computes the parking status of the street segment you're driving on
*before* you need it, and delivers it as a glanceable Live Activity color
(green / yellow / red in the Dynamic Island and Lock Screen) plus a brief
audio cue that ducks — never pauses — your music. A camera fallback interprets
ambiguous signs with a vision LLM.

Read the full product brief in [docs/HANDOFF.md](docs/HANDOFF.md) and the
technical design in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Repository layout

```
ios/                     SwiftUI app (XcodeGen project)
  ParkWell/              app target — services, views, rule engine
  ParkWellWidgets/       Live Activity (Dynamic Island + Lock Screen)
  Shared/                models + ActivityAttributes shared with the widget
  ParkWellTests/         rule engine unit tests
  project.yml            XcodeGen definition (the .xcodeproj is generated)
supabase/
  migrations/            schema: static layer + dynamic overlay layer
  seed.sql               SAMPLE dev data — not survey-accurate
  functions/hrm-alerts/      polls HRM pages for the winter parking ban
  functions/interpret-sign/  Claude vision call for the camera fallback
tools/sign-mapper/       phone web tool for hand-mapping zones B/C/H
docs/                    handoff brief + architecture
```

## Getting started

### iOS app (requires a Mac with Xcode 15+)

```sh
brew install xcodegen
cd ios
xcodegen generate
open ParkWell.xcodeproj
```

Set your Supabase URL and anon key in `ios/ParkWell/Config.swift`, then run
the `ParkWell` scheme. Run the tests with **⌘U** (the rule engine — paid
windows, the 2026-07-18 Saturday changeover, winter-ban override, staleness —
is covered in `ParkWellTests`).

### Backend

```sh
supabase init          # if not linked yet
supabase db push       # applies migrations/0001_initial_schema.sql
supabase db seed       # loads the SAMPLE dev dataset
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
supabase functions deploy interpret-sign
supabase functions deploy hrm-alerts --no-verify-jwt
```

Schedule `hrm-alerts` every ~30 minutes (pg_cron + pg_net, or any external
cron hitting the function URL) so the winter-ban flag tracks HRM's
announcements.

### Mapping real data

The seed contains four sample segments so the pipeline runs end-to-end. The
real dataset comes from walking zones B/C/H with
[tools/sign-mapper](tools/sign-mapper/README.md) (~600 signs) and translating
the export into `street_segments` + `segment_rules` rows.

## Status

Phase 1 scaffold: core pipeline (location → segment → verdict → Live Activity
+ audio), tested rule engine, two-layer schema, winter-ban scraper skeleton,
sign scanner, and mapping tool are in place. Sample data, scraper phrase
patterns, and config keys need real-world values before TestFlight. CarPlay
is Phase 2 — apply for the entitlement once Phase 1 validates.

## Disclaimer

Posted signs always win. GPS can be inaccurate, rules change, and ParkWell
cannot guarantee against a ticket.
