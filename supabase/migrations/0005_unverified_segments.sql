-- Street centerline import: every open public street in the Regional Centre
-- becomes a segment with no rules and verified = false. The client renders
-- these as "likely OK" (pale green) — in Nova Scotia street parking is legal
-- by default unless posted otherwise — visually distinct from verified data.
alter table street_segments add column verified boolean not null default true;
