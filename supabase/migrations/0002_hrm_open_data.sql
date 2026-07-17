-- Support for importing HRM's open-data parking layers
-- (https://data-hrm.hub.arcgis.com — discovered after the handoff doc
-- assumed no public GIS existed; see tools/hrm-import).

-- Zone boundary polygons (raw GeoJSON geometry, [lon, lat] order) — lets the
-- client geofence real zone shapes instead of a hand-drawn bounding box.
alter table zones add column boundary jsonb;

-- Provenance on segments: 'manual' (hand-mapped / sign-mapper) vs
-- 'hrm_arcgis' (imported). Imports delete-and-replace only their own rows,
-- so hand-mapped data always survives a re-import.
alter table street_segments add column source text not null default 'manual';
alter table street_segments add column source_id text;
create index street_segments_source_idx on street_segments (source, source_id);

-- HRM enforces the overnight winter ban per zone (Zone 1 Central vs Zone 2
-- Non-Central). Boundary is raw GeoJSON geometry ([lon, lat] order).
create table winter_ban_zones (
    id uuid primary key default gen_random_uuid(),
    city_code text not null references cities(code),
    zone_number int not null,
    region text,
    boundary jsonb not null
);

alter table winter_ban_zones enable row level security;
create policy "anon read winter ban zones" on winter_ban_zones for select using (true);
