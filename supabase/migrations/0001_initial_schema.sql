-- ParkWell initial schema.
-- Two layers, kept separate by design (see docs/HANDOFF.md §6):
--   Static layer:  zones, street_segments, segment_rules  (hand-mapped, changes rarely)
--   Dynamic layer: winter_ban_status, street_cleaning     (live feed, changes daily/seasonally)
-- Everything is per-city from day one so a second city is a data problem,
-- not a schema migration.

create table cities (
    code text primary key,          -- e.g. 'hfx'
    name text not null,
    timezone text not null          -- IANA, e.g. 'America/Halifax'
);

create table zones (
    city_code text not null references cities(code),
    code text not null,             -- 'B', 'C', 'H'
    name text not null,
    primary key (city_code, code)
);

-- One side of one block face — the atomic unit of the static layer.
create table street_segments (
    id uuid primary key default gen_random_uuid(),
    city_code text not null references cities(code),
    zone_code text,                 -- nullable: not all segments are in a paid zone
    street_name text not null,
    side text not null,             -- 'north' | 'south' | 'east' | 'west' | 'both'
    -- [[lat, lon], ...] — jsonb keeps the client decoding trivial; move to
    -- PostGIS only if/when server-side spatial queries are actually needed.
    polyline jsonb not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index street_segments_city_idx on street_segments (city_code);

create table segment_rules (
    id uuid primary key default gen_random_uuid(),
    segment_id uuid not null references street_segments(id) on delete cascade,
    kind text not null check (kind in
        ('free', 'paid', 'time_limited', 'permit_only', 'loading_zone', 'no_stopping', 'accessible')),
    -- Array of windows; empty array = rule applies at all times. Each window:
    --   { "weekdays": [2,3,4,5,6],       -- 1=Sun ... 7=Sat (Apple Calendar convention)
    --     "start_minute": 480,            -- minutes after local midnight
    --     "end_minute": 1080,
    --     "effective_from": "2026-07-18T00:00:00-03:00",   -- optional
    --     "effective_until": null }                         -- optional
    -- effective_* lets schedule changes ship in data ahead of the changeover date.
    windows jsonb not null default '[]'::jsonb,
    time_limit_minutes int,
    note text
);

create index segment_rules_segment_idx on segment_rules (segment_id);

-- ── Dynamic overlay layer ────────────────────────────────────────────────

-- Single row per city; flipped by the hrm-alerts edge function.
create table winter_ban_status (
    id int primary key default 1 check (id = 1),   -- singleton until city #2
    city_code text not null references cities(code),
    active boolean not null default false,
    message text,
    source_url text,
    updated_at timestamptz not null default now()
);

create table street_cleaning (
    id uuid primary key default gen_random_uuid(),
    segment_id uuid not null references street_segments(id) on delete cascade,
    weekday int not null check (weekday between 1 and 7),  -- 1=Sun ... 7=Sat
    start_minute int not null,
    end_minute int not null
);

create index street_cleaning_segment_idx on street_cleaning (segment_id);

-- ── Row-level security: everything read-only for the anon key ────────────
-- Writes happen only via the service-role key (edge functions, data entry).

alter table cities enable row level security;
alter table zones enable row level security;
alter table street_segments enable row level security;
alter table segment_rules enable row level security;
alter table winter_ban_status enable row level security;
alter table street_cleaning enable row level security;

create policy "anon read cities" on cities for select using (true);
create policy "anon read zones" on zones for select using (true);
create policy "anon read segments" on street_segments for select using (true);
create policy "anon read rules" on segment_rules for select using (true);
create policy "anon read winter ban" on winter_ban_status for select using (true);
create policy "anon read street cleaning" on street_cleaning for select using (true);
