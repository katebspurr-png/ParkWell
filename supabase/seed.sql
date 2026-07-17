-- Development seed data.
--
-- ⚠️ SAMPLE GEOMETRY AND RULES — a handful of plausible downtown segments so
-- the app pipeline can be exercised end-to-end. These are NOT survey-accurate
-- and must be replaced by the real hand-mapped dataset for zones B, C, H
-- (collected with tools/sign-mapper). Do not ship this seed to production.

insert into cities (code, name, timezone) values
    ('hfx', 'Halifax Regional Municipality', 'America/Halifax');

insert into zones (city_code, code, name) values
    ('hfx', 'B', 'Downtown Halifax North'),
    ('hfx', 'C', 'Downtown Halifax South'),
    ('hfx', 'H', 'Downtown Dartmouth');

-- Paid-hours window set shared by zones B/C/H:
--   Mon–Fri 08:00–18:00 (standing rule)
--   Sat     08:00–18:00 effective 2026-07-18 (HRM schedule expansion)
-- Weekday numbers use the Apple Calendar convention: 1=Sun … 7=Sat.

-- Barrington St (Zone C)
with seg as (
    insert into street_segments (city_code, zone_code, street_name, side, polyline) values
        ('hfx', 'C', 'Barrington St', 'east',
         '[[44.6476, -63.5728], [44.6488, -63.5722]]'::jsonb)
    returning id
)
insert into segment_rules (segment_id, kind, windows)
select id, 'paid', '[
    {"weekdays": [2,3,4,5,6], "start_minute": 480, "end_minute": 1080},
    {"weekdays": [7], "start_minute": 480, "end_minute": 1080,
     "effective_from": "2026-07-18T00:00:00-03:00"}
]'::jsonb from seg;

-- Spring Garden Rd (Zone C) — paid + a rush-hour no-stopping overlay
with seg as (
    insert into street_segments (city_code, zone_code, street_name, side, polyline) values
        ('hfx', 'C', 'Spring Garden Rd', 'south',
         '[[44.6430, -63.5790], [44.6435, -63.5755]]'::jsonb)
    returning id
)
insert into segment_rules (segment_id, kind, windows, note)
select id, 'paid', '[
    {"weekdays": [2,3,4,5,6], "start_minute": 480, "end_minute": 1080},
    {"weekdays": [7], "start_minute": 480, "end_minute": 1080,
     "effective_from": "2026-07-18T00:00:00-03:00"}
]'::jsonb, null from seg
union all
select id, 'no_stopping', '[
    {"weekdays": [2,3,4,5,6], "start_minute": 420, "end_minute": 540}
]'::jsonb, 'Weekday morning rush-hour clearway' from seg;

-- Argyle St (Zone B) — loading zone, 15 min
with seg as (
    insert into street_segments (city_code, zone_code, street_name, side, polyline) values
        ('hfx', 'B', 'Argyle St', 'west',
         '[[44.6480, -63.5752], [44.6490, -63.5747]]'::jsonb)
    returning id
)
insert into segment_rules (segment_id, kind, windows, time_limit_minutes)
select id, 'loading_zone', '[
    {"weekdays": [2,3,4,5,6], "start_minute": 420, "end_minute": 1080}
]'::jsonb, 15 from seg;

-- Portland St, Dartmouth (Zone H) — paid, plus Wednesday street cleaning
with seg as (
    insert into street_segments (city_code, zone_code, street_name, side, polyline) values
        ('hfx', 'H', 'Portland St', 'north',
         '[[44.6654, -63.5679], [44.6660, -63.5652]]'::jsonb)
    returning id
), rules as (
    insert into segment_rules (segment_id, kind, windows)
    select id, 'paid', '[
        {"weekdays": [2,3,4,5,6], "start_minute": 480, "end_minute": 1080},
        {"weekdays": [7], "start_minute": 480, "end_minute": 1080,
         "effective_from": "2026-07-18T00:00:00-03:00"}
    ]'::jsonb from seg
)
insert into street_cleaning (segment_id, weekday, start_minute, end_minute)
select id, 4, 480, 720 from seg;  -- Wednesday 08:00–12:00

-- Winter ban singleton, off by default; the hrm-alerts function flips it.
insert into winter_ban_status (id, city_code, active, message, source_url) values
    (1, 'hfx', false, null, 'https://www.halifax.ca/transportation/winter-operations');
