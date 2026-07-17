# Project Handoff: Live Parking Status App (working title)

## 1. One-line summary
An iOS app that tells drivers, in real time and near-instantly, whether the spot they're passing is legal to park in right now — starting with downtown Halifax/Dartmouth, designed around the moment of driving and spotting a space, not around browsing a map beforehand.

## 2. Problem & core insight
Parking apps that already exist (SpotAngels, ParkUsher, a Copenhagen tool called Legal Parking, a sign-decoder called ParkingFight) all solve "look this up" — browse a map before you leave, or snap a photo of a confusing sign once you're already parked. None of them solve the actual high-stress moment: you're driving, you see an open space, you have about two seconds to decide before you pass it.

That moment can't be served by a map you pinch-zoom or a photo you snap — by the time you've done either, the spot's gone. It needs status that's already computed before you need it, delivered as a single glance or an audio cue, not a lookup you initiate. This is the differentiated bet. Sign-reading/interpretation itself is now close to commodity (any decent vision model handles it) — the real product is the live in-motion alert layer, not the data lookup.

**Competitive note:** none of the parking apps checked show up in CarPlay app roundups, while an analogous "find X nearby while driving" category (EV charging — ChargePoint, PlugShare) does have real CarPlay presence. That's the open lane.

## 3. MVP scope (Phase 1 — build this first)
- iPhone app (Swift/SwiftUI), single city: downtown Halifax + Dartmouth core (paid parking zones B, C, H as the initial coverage area — roughly 600+ signs across those three zones, a hand-mappable scope).
- Background location tracking while the app is active/driving.
- **Glanceable status surface:** an iOS Live Activity (Dynamic Island + Lock Screen) showing a single color state — green / yellow / red — for the current street segment.
- **Audio cue:** a short tone or brief spoken status ("legal, no time limit" / "loading zone, 15 min") as the user's location crosses into a new parking-rule segment. Must duck whatever music/podcast is already playing (`AVAudioSession`), not interrupt/pause it.
- **Camera fallback:** for ambiguous or unmapped signage, let the user snap a photo and get an AI-interpreted plain-English verdict (can reuse a vision-capable LLM call for this — this part is the "commodity" layer, don't over-invest).
- Static rules only need to cover what's actually posted: paid parking hours (currently weekdays 8am–6pm, expanding to Saturdays 8am–6pm as of July 18, 2026, in zones B/C/H), permit-only signage, no-stopping/tow zones, accessible parking.

## 4. Explicitly out of scope for MVP
- CarPlay integration — this is the Phase 2 goal, not Phase 1. See section 8.
- Any city beyond Halifax/Dartmouth core.
- Payment/session integration with HRM's HotSpot paid-parking system (nice-to-have later, not core to the "can I park here" question).
- Crowdsourced sign-reporting/verification network (v2 feature once there's a user base to crowdsource from).
- Android.

## 5. Target platform & stack
- **Client:** Swift/SwiftUI, iOS. Same general pattern as existing Resonance and BioLog projects.
- **Live Activity:** ActivityKit for the Dynamic Island/Lock Screen glanceable surface. This choice is deliberate: Apple has been bridging Live Activities/widgets directly into CarPlay itself, so this Phase 1 surface isn't throwaway work — it's architecturally the same thing that extends into the Phase 2 CarPlay build.
- **Backend:** Supabase (matches existing BioLog stack) — store the per-city rules dataset (zones, static signs, dynamic overlay flags) and serve it to the client.
- **Audio:** `AVAudioSession` with a ducking category, not exclusive playback.
- **Vision fallback:** API call to a vision-capable LLM for photo-based sign interpretation.

## 6. Data model (design as per-city config from day one, even though only Halifax ships in Phase 1)
Two layers, kept separate:

**Static layer** (changes rarely, hand-mapped/scraped once per city):
- Street segment geometry (which side of which block)
- Base rule type: paid parking / permit-only / no-stopping / accessible / free
- Time windows the rule applies (e.g., paid 8am–6pm Mon–Sat)
- Zone identifier (B, C, H, etc.)

**Dynamic overlay layer** (changes daily/seasonally, needs a live feed, not a one-time hand-map):
- Winter parking ban status (HRM triggers this ad hoc based on weather forecasts — was enforced 31+ times in one recent season; needs to be scraped/polled from HRM's public alert source, not hardcoded)
- Street cleaning day-of-week per street (varies by street in peninsular Halifax)
- Any temporary/construction signage if you get to crowdsourcing later

The dynamic overlay is the genuinely hard, differentiated engineering problem — not the sign-reading. Treat it as the core build, not a stretch feature.

## 7. Data sourcing plan (Halifax)
- No public GIS/API for on-street parking rules was found on HRM's site — the data exists as PDFs, web pages, and physical signage only, not machine-readable.
- Plan: build a scraper for HRM's parking pages and alert/news feed (same skill set already used for the Halifax Now scrapers) to catch the winter-ban trigger and any posted schedule changes.
- Hand-map the static layer for zones B, C, H as the initial MVP dataset (~600 signs — realistic for manual mapping, possibly with a simple internal tool to speed up data entry while walking/driving the zones).

## 8. Phase 2 — CarPlay (the "ultimate goal," not the MVP)
- Apple has an official **Parking** category in the CarPlay framework, with its own template APIs — this is a first-class supported path, not a workaround.
- Apple's rules for that category actually reinforce the product design: parking apps must provide meaningful functionality relevant to driving and can't show non-parking locations on the map, and — more importantly — developers should avoid instructing users to interact with their iPhone while driving, and all user flows must be navigable without requiring iPhone interaction. Voice/audio-first isn't a compromise for CarPlay; it's close to a requirement, so Phase 1's audio-cue work carries forward directly.
- **Action item, start early:** the CarPlay entitlement requires applying through Apple's developer program with app details (including category) and going through Apple's review before you're approved to build against the framework — this has real lead time, so apply once Phase 1 has validated the concept, not after Phase 2 code is written.

## 9. Non-functional requirements
- **Battery:** continuous background GPS is expensive — investigate significant-location-change APIs or geofencing on known zone boundaries rather than continuous high-accuracy polling, especially outside the mapped zones.
- **Privacy:** location data handling needs a clear, minimal-retention story; background location permission justification will be scrutinized in App Store review (same category of scrutiny as Waze/Google Maps — cite the core "why" clearly in the permission prompt).
- **Offline/degraded behavior:** if the dynamic overlay feed hasn't refreshed recently, the app should be honest about staleness rather than showing a confident green/red on stale data.
- **Legal disclaimer:** signs win. Every comparable app in this space (ParkingFight, Legal Parking, ParkUsher) explicitly disclaims that GPS can be inaccurate and the app can't guarantee against a ticket — carry the same honest framing.

## 10. Open questions for early build decisions
- Exact audio cue design: tone-only vs. brief spoken status vs. user-configurable?
- How much of the static-layer hand-mapping can be semi-automated (e.g., photograph-and-geotag while walking the zones, feed through the same vision-LLM used for the camera fallback) vs. fully manual entry?
- Live Activity update frequency/battery tradeoff — how often can the status realistically refresh without killing battery life?
- Whether to gate the MVP behind TestFlight with a small group (e.g., seeded from the Halifax Now audience) before a public App Store listing.

## 11. Reference: competitive landscape (from research discussion)
- **ParkUsher** — live map (green/red street lines) + camera sign-scanner, covers Montreal, NYC, Toronto, Boston, SF, Seattle, Vancouver. No Halifax coverage found.
- **SpotAngels** — markets itself as "Waze for parking" but functions as a browse-a-map lookup tool, not an in-motion alert system.
- **ParkingFight** — pure photo-upload sign decoder + ticket-appeal letter generator.
- **Legal Parking** (Copenhagen) — single-city AI sign reader, explicitly warns GPS accuracy issues in dense urban areas.
