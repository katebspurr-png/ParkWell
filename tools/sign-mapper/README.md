# Sign Mapper

A single-file web tool for hand-mapping the static layer while walking zones
B, C, and H (~600 signs).

## Use

1. Serve `index.html` over HTTPS (geolocation requires it) — e.g.
   `npx serve` behind a tunnel, or host it anywhere static.
2. Open it on your phone, grant location access.
3. At each sign: fill in street/side once per block, type the sign text into
   the notes field, tap the rule-type button. GPS + timestamp are captured
   automatically. Entries persist in localStorage between sessions.
4. Tap **Export JSON** at the end of the walk.

## From raw points to segments

The export is a list of geotagged sign observations, not segments. The
conversion (cluster points per block face → draw the segment polyline →
translate the noted sign text into `segment_rules` windows) is currently a
manual pass over the JSON. Semi-automating it — including feeding the sign
photos through the same `interpret-sign` function used by the app's camera
fallback — is an open question in the handoff doc (§10) worth exploring once
a first walk's data shows the real shape of the problem.
