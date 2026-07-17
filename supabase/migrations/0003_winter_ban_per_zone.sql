-- HRM enforces the overnight winter ban per zone (Zone 1 - Central,
-- Zone 2 - Non-Central) and announces each independently. Track both;
-- `active` remains the any-zone rollup the Phase 1 client consumes.
alter table winter_ban_status
    add column zone1_active boolean not null default false,
    add column zone2_active boolean not null default false;
