-- Pay station locations (HRM open data). Surfaced on paid-parking verdicts
-- so the driver has the station number for the HotSpot payment app without
-- hunting for the sticker.
--
-- NOTE: tid is HRM's station ID (e.g. 'PS125'). Whether HotSpot displays the
-- same number is unverified — confirm against a physical sticker and adjust
-- the import if HotSpot uses its own numbering.
create table pay_stations (
    id uuid primary key default gen_random_uuid(),
    city_code text not null references cities(code),
    tid text not null,
    zone_code text,
    street text,
    latitude double precision not null,
    longitude double precision not null,
    source text not null default 'hrm_arcgis'
);

create index pay_stations_city_idx on pay_stations (city_code);

alter table pay_stations enable row level security;
create policy "anon read pay stations" on pay_stations for select using (true);
