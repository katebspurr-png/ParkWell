-- Weekday on-street rates. HRM uses time-of-day demand pricing (a zone's
-- rate changes through the day), so a single hourly figure can't represent
-- a zone honestly — store the verified schedule instead and let the client
-- resolve "rate right now". Null schedule = paid zone with unconfirmed
-- pricing: ranked after known rates, never displayed as a number.
--
-- Source: halifax.ca/transportation/parking/street-parking, weekday table
-- effective 2026-07-15 (post 25% increase). Zones I and J have no published
-- rates there, so they stay null. Saturday downtown pricing (free first
-- hour, then $2 flat in B/C/H from 2026-07-18) is not covered here — the
-- client only resolves this schedule Monday–Friday.
--
-- Windows are [start_minute, end_minute) after local midnight.
alter table zones add column weekday_rate_schedule jsonb;

-- Upsert so a fresh database gets rates even before the HRM import runs
-- (the import's boundary upsert leaves this column untouched).
insert into zones (city_code, code, name, weekday_rate_schedule) values
  ('hfx', 'A', 'Zone A', '[{"start_minute":480,"end_minute":1020,"rate_cents":250},{"start_minute":1020,"end_minute":1080,"rate_cents":150}]'::jsonb),
  ('hfx', 'B', 'Zone B', '[{"start_minute":480,"end_minute":600,"rate_cents":325},{"start_minute":600,"end_minute":780,"rate_cents":475},{"start_minute":780,"end_minute":1020,"rate_cents":325},{"start_minute":1020,"end_minute":1080,"rate_cents":150}]'::jsonb),
  ('hfx', 'C', 'Zone C', '[{"start_minute":480,"end_minute":660,"rate_cents":325},{"start_minute":660,"end_minute":840,"rate_cents":475},{"start_minute":840,"end_minute":1020,"rate_cents":325},{"start_minute":1020,"end_minute":1080,"rate_cents":150}]'::jsonb),
  ('hfx', 'D', 'Zone D', '[{"start_minute":480,"end_minute":840,"rate_cents":475},{"start_minute":840,"end_minute":1020,"rate_cents":250},{"start_minute":1020,"end_minute":1080,"rate_cents":150}]'::jsonb),
  ('hfx', 'E', 'Zone E', '[{"start_minute":480,"end_minute":1020,"rate_cents":250},{"start_minute":1020,"end_minute":1080,"rate_cents":150}]'::jsonb),
  ('hfx', 'F', 'Zone F', '[{"start_minute":480,"end_minute":1020,"rate_cents":250},{"start_minute":1020,"end_minute":1080,"rate_cents":150}]'::jsonb),
  ('hfx', 'G', 'Zone G', '[{"start_minute":480,"end_minute":1020,"rate_cents":250},{"start_minute":1020,"end_minute":1080,"rate_cents":150}]'::jsonb),
  ('hfx', 'H', 'Zone H', '[{"start_minute":480,"end_minute":660,"rate_cents":325},{"start_minute":660,"end_minute":840,"rate_cents":400},{"start_minute":840,"end_minute":1080,"rate_cents":150}]'::jsonb)
on conflict (city_code, code) do update set weekday_rate_schedule = excluded.weekday_rate_schedule;
