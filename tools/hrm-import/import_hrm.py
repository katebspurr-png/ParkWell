#!/usr/bin/env python3
"""Fetch HRM open-data parking layers and generate SQL for the ParkWell schema.

Layers imported (all public ArcGIS feature services from HRM's open data org):

  Parking Pay Zones               -> zones.boundary (polygons, zones A-J)
  Commuter Permit Parking Streets -> street_segments + permit_only rules
  Accessible Parking Spots        -> street_segments + accessible rules
  Overnight Winter Parking Ban    -> winter_ban_zones (Zone 1 / Zone 2)
  Parking Pay Stations            -> pay_stations.geojson (mapping aid only,
                                     not imported — pinpoints paid block faces
                                     for the hand-mapping pass)

The generated SQL is idempotent: it delete-and-replaces only rows with
source = 'hrm_arcgis', so hand-mapped segments are never touched.

Usage:
  python3 tools/hrm-import/import_hrm.py
  # -> writes supabase/imports/hrm_import.sql and tools/hrm-import/pay_stations.geojson
  # Paste/run the SQL in the Supabase SQL Editor (after migration 0002).

Stdlib only — no dependencies.
"""

import json
import sys
import uuid
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

ARCGIS_ITEM_URL = "https://www.arcgis.com/sharing/rest/content/items/{item_id}?f=json"

# ArcGIS Online item IDs (owner: opendata_HRM / halifax_agol).
ITEMS = {
    "pay_zones": "00e12ac25a244050b1842758c786f6fc",
    "commuter_permit_streets": "395941097f1b4e1f9ae19eae43cca1cc",
    "accessible_spots": "90be8d1040e54793a29a80d1f94d942e",
    "pay_stations": "a4b02c8ea43c436badd41ab82bcceed2",
    "winter_ban_zone1": "236a966107a24dd3a13f1f254a5afd74",
    "winter_ban_zone2": "ef3b5ed0b7db4517bcdbe3a1e5dd7814",
    "street_centerlines": "560fec412dd044b08ae52a8575a215d4",
}

# Street centerline scope: Regional Centre communities first (expand later by
# adding community names). Excludes expressways (no street parking) and
# private/military roads (not ours to make claims about).
CENTERLINE_WHERE = (
    "(GSA_LEFT IN ('HALIFAX','DARTMOUTH') OR GSA_RIGHT IN ('HALIFAX','DARTMOUTH'))"
    " AND STR_STATUS='OPEN'"
    " AND (ST_CLASS IS NULL OR ST_CLASS <> 'EXPRESSWAY')"
    " AND (OWN IS NULL OR OWN NOT IN ('PRIV','DND'))"
)

CITY = "hfx"
NAMESPACE = uuid.uuid5(uuid.NAMESPACE_URL, "parkwell.hrm_arcgis")

REPO_ROOT = Path(__file__).resolve().parents[2]
SQL_OUT = REPO_ROOT / "supabase" / "imports" / "hrm_import.sql"
STATIONS_OUT = Path(__file__).resolve().parent / "pay_stations.geojson"


def fetch_json(url: str) -> dict:
    req = Request(url, headers={"User-Agent": "ParkWell hrm-import/0.1"})
    with urlopen(req, timeout=60) as resp:
        return json.load(resp)


def resolve_layer_url(item_id: str) -> str:
    """Item -> feature service URL -> first layer's query endpoint."""
    item = fetch_json(ARCGIS_ITEM_URL.format(item_id=item_id))
    service_url = item["url"].rstrip("/")
    if service_url.split("/")[-1].isdigit():
        return service_url
    root = fetch_json(f"{service_url}?f=json")
    layer_id = root["layers"][0]["id"]
    return f"{service_url}/{layer_id}"


def query_features(layer_url: str, where: str = "1=1") -> list[dict]:
    """Query all features as GeoJSON (WGS84 lon/lat), paginating."""
    features: list[dict] = []
    offset = 0
    page = 1000
    while True:
        params = urlencode({
            "where": where,
            "outFields": "*",
            "outSR": 4326,
            "f": "geojson",
            "resultOffset": offset,
            "resultRecordCount": page,
        })
        data = fetch_json(f"{layer_url}/query?{params}")
        batch = data.get("features", [])
        features.extend(batch)
        if len(batch) < page:
            return features
        offset += len(batch)


def path_midpoint(path: list) -> tuple[float, float]:
    """(lat, lon) midpoint-ish of a GeoJSON [lon, lat] path."""
    lon, lat = path[len(path) // 2]
    return lat, lon


def approx_distance_m(a: tuple[float, float], b: tuple[float, float]) -> float:
    """Equirectangular distance, fine at city scale."""
    import math
    lat_m = (a[0] - b[0]) * 111_320
    lon_m = (a[1] - b[1]) * 111_320 * math.cos(math.radians(a[0]))
    return (lat_m * lat_m + lon_m * lon_m) ** 0.5


def street_title(name: str | None) -> str | None:
    return name.strip().title() if name and name.strip() else None


def sql_str(value) -> str:
    if value is None:
        return "null"
    return "'" + str(value).replace("'", "''") + "'"


def stable_id(source_id: str) -> str:
    return str(uuid.uuid5(NAMESPACE, source_id))


def latlon_polyline(coords_lonlat: list) -> list:
    """GeoJSON [lon, lat] -> app convention [lat, lon], rounded."""
    return [[round(lat, 6), round(lon, 6)] for lon, lat in coords_lonlat]


def line_paths(geometry: dict) -> list[list]:
    if geometry is None:
        return []
    if geometry["type"] == "LineString":
        return [geometry["coordinates"]]
    if geometry["type"] == "MultiLineString":
        return geometry["coordinates"]
    return []


def main() -> None:
    out: list[str] = []
    out.append("-- Generated by tools/hrm-import/import_hrm.py — do not hand-edit.")
    out.append("-- Requires migration 0002_hrm_open_data.sql. Idempotent: replaces")
    out.append("-- only source='hrm_arcgis' rows; manual data is untouched.\n")
    out.append("begin;")
    out.append("delete from street_segments where source = 'hrm_arcgis';")
    out.append(f"delete from winter_ban_zones where city_code = {sql_str(CITY)};")
    out.append(f"delete from pay_stations where city_code = {sql_str(CITY)} and source = 'hrm_arcgis';\n")

    # ── Pay zone boundaries ─────────────────────────────────────────────
    print("Fetching pay zones…", file=sys.stderr)
    zones = query_features(resolve_layer_url(ITEMS["pay_zones"]))
    for feat in zones:
        raw = (feat["properties"].get("ZONE") or "").strip()      # "ZONE B"
        code = raw.replace("ZONE", "").strip()
        if not code:
            continue
        boundary = json.dumps(feat["geometry"], separators=(",", ":"))
        out.append(
            f"insert into zones (city_code, code, name, boundary) values "
            f"({sql_str(CITY)}, {sql_str(code)}, {sql_str('Zone ' + code)}, {sql_str(boundary)}::jsonb) "
            f"on conflict (city_code, code) do update set boundary = excluded.boundary;"
        )
    print(f"  {len(zones)} zone polygons", file=sys.stderr)

    # ── Street centerlines (fetched early: also names the permit streets) ─
    print("Fetching street centerlines (Regional Centre)…", file=sys.stderr)
    centerlines = query_features(resolve_layer_url(ITEMS["street_centerlines"]), where=CENTERLINE_WHERE)
    # (midpoint, display name) lookup for the spatial join below.
    centerline_index = []
    for feat in centerlines:
        name = street_title(feat["properties"].get("FULL_NAME"))
        if not name:
            continue
        for path in line_paths(feat.get("geometry")):
            if len(path) >= 2:
                centerline_index.append((path_midpoint(path), name))
    print(f"  {len(centerlines)} centerline segments", file=sys.stderr)

    def nearest_street_name(path: list, max_meters: float = 60) -> str | None:
        mid = path_midpoint(path)
        best_name, best_d = None, max_meters
        for cl_mid, cl_name in centerline_index:
            d = approx_distance_m(mid, cl_mid)
            if d < best_d:
                best_name, best_d = cl_name, d
        return best_name

    # ── Commuter/permit parking streets -> segments + permit_only ───────
    print("Fetching permit parking streets…", file=sys.stderr)
    streets = query_features(resolve_layer_url(ITEMS["commuter_permit_streets"]))
    n_seg = 0
    out.append("")
    for feat in streets:
        props = feat["properties"]
        ppid = props.get("PPID") or f"OBJ{props.get('OBJECTID')}"
        commuter = props.get("COMMUTER") == "Y"
        for i, path in enumerate(line_paths(feat.get("geometry"))):
            if len(path) < 2:
                continue
            source_id = f"permit:{ppid}:{i}"
            seg_id = stable_id(source_id)
            rule_id = stable_id(source_id + ":rule")
            polyline = json.dumps(latlon_polyline(path), separators=(",", ":"))
            name = nearest_street_name(path) or f"Permit street {ppid}"
            note = (
                f"HRM permit parking ({ppid})"
                + (", commuter permits eligible" if commuter else "")
                + " — posted hours unverified, confirm on-site"
            )
            out.append(
                f"insert into street_segments (id, city_code, zone_code, street_name, side, polyline, source, source_id) values "
                f"({sql_str(seg_id)}, {sql_str(CITY)}, null, {sql_str(name)}, 'both', "
                f"{sql_str(polyline)}::jsonb, 'hrm_arcgis', {sql_str(source_id)});"
            )
            out.append(
                f"insert into segment_rules (id, segment_id, kind, windows, note) values "
                f"({sql_str(rule_id)}, {sql_str(seg_id)}, 'permit_only', '[]'::jsonb, {sql_str(note)});"
            )
            n_seg += 1
    print(f"  {n_seg} permit street segments", file=sys.stderr)

    # ── Accessible parking spots -> short segments + accessible ─────────
    print("Fetching accessible spots…", file=sys.stderr)
    spots = query_features(resolve_layer_url(ITEMS["accessible_spots"]))
    n_spots = 0
    out.append("")
    for feat in spots:
        geometry = feat.get("geometry")
        if not geometry or geometry["type"] != "Point":
            continue
        props = feat["properties"]
        lon, lat = geometry["coordinates"][:2]
        source_id = f"accessible:{props.get('ACCPRKID') or props.get('OBJECTID')}"
        seg_id = stable_id(source_id)
        rule_id = stable_id(source_id + ":rule")
        # A ~20 m stub segment centered on the point so the matcher can hit it;
        # orientation is unknown, refine during the verification walk.
        polyline = json.dumps(
            [[round(lat - 0.00009, 6), round(lon, 6)], [round(lat + 0.00009, 6), round(lon, 6)]],
            separators=(",", ":"),
        )
        street = (props.get("STREET_NAME") or "Accessible parking").strip().title()
        details = [
            f"{props['NUMSPOTS']} spot(s)" if props.get("NUMSPOTS") else None,
            f"between {props['FROM_STR']} and {props['TO_STR']}"
            if props.get("FROM_STR") and props.get("TO_STR") else None,
            f"duration: {props['DURATION']}" if props.get("DURATION") else None,
            f"status: {props['STATUS']}" if props.get("STATUS") else None,
        ]
        note = "HRM accessible spot — " + "; ".join(d for d in details if d)
        out.append(
            f"insert into street_segments (id, city_code, zone_code, street_name, side, polyline, source, source_id) values "
            f"({sql_str(seg_id)}, {sql_str(CITY)}, null, {sql_str(street)}, 'both', "
            f"{sql_str(polyline)}::jsonb, 'hrm_arcgis', {sql_str(source_id)});"
        )
        out.append(
            f"insert into segment_rules (id, segment_id, kind, windows, note) values "
            f"({sql_str(rule_id)}, {sql_str(seg_id)}, 'accessible', '[]'::jsonb, {sql_str(note)});"
        )
        n_spots += 1
    print(f"  {n_spots} accessible spot segments", file=sys.stderr)

    # ── Centerlines -> unverified "likely OK" segments ──────────────────
    out.append("")
    n_centerline = 0
    seen_centerline_ids: set[str] = set()
    for feat in centerlines:
        props = feat["properties"]
        name = street_title(props.get("FULL_NAME"))
        if not name:
            continue
        asset = props.get("ASSETID") or f"OBJ{props.get('OBJECTID')}"
        for i, path in enumerate(line_paths(feat.get("geometry"))):
            if len(path) < 2:
                continue
            source_id = f"centerline:{asset}:{i}"
            # HRM asset ids are occasionally shared by distinct streets;
            # disambiguate deterministically so stable_id stays unique.
            n_dup = 0
            while source_id in seen_centerline_ids:
                n_dup += 1
                source_id = f"centerline:{asset}:{i}:dup{n_dup}"
            seen_centerline_ids.add(source_id)
            polyline = json.dumps(latlon_polyline(path), separators=(",", ":"))
            out.append(
                f"insert into street_segments (id, city_code, zone_code, street_name, side, polyline, source, source_id, verified) values "
                f"({sql_str(stable_id(source_id))}, {sql_str(CITY)}, null, {sql_str(name)}, 'both', "
                f"{sql_str(polyline)}::jsonb, 'hrm_arcgis', {sql_str(source_id)}, false);"
            )
            n_centerline += 1
    print(f"  {n_centerline} unverified centerline segments", file=sys.stderr)

    # ── Winter ban zones ────────────────────────────────────────────────
    out.append("")
    for zone_number, key in ((1, "winter_ban_zone1"), (2, "winter_ban_zone2")):
        print(f"Fetching winter ban zone {zone_number}…", file=sys.stderr)
        feats = query_features(resolve_layer_url(ITEMS[key]))
        for feat in feats:
            region = feat["properties"].get("REGION")
            boundary = json.dumps(feat["geometry"], separators=(",", ":"))
            out.append(
                f"insert into winter_ban_zones (city_code, zone_number, region, boundary) values "
                f"({sql_str(CITY)}, {zone_number}, {sql_str(region)}, {sql_str(boundary)}::jsonb);"
            )
        print(f"  {len(feats)} polygon(s)", file=sys.stderr)

    # ── Pay stations -> pay_stations table (+ GeoJSON mapping aid) ──────
    print("Fetching pay stations…", file=sys.stderr)
    stations = query_features(resolve_layer_url(ITEMS["pay_stations"]))
    out.append("")
    n_stations = 0
    for feat in stations:
        geometry = feat.get("geometry")
        if not geometry or geometry["type"] != "Point":
            continue
        props = feat["properties"]
        # ASSETSTAT 'INS' = installed; skip removed/planned stations.
        if props.get("ASSETSTAT") and props["ASSETSTAT"] != "INS":
            continue
        lon, lat = geometry["coordinates"][:2]
        out.append(
            f"insert into pay_stations (city_code, tid, zone_code, street, latitude, longitude) values "
            f"({sql_str(CITY)}, {sql_str(props.get('TID') or props.get('ASSETID'))}, "
            f"{sql_str(props.get('PKNGZONE'))}, {sql_str(props.get('LOCATION'))}, "
            f"{round(lat, 6)}, {round(lon, 6)});"
        )
        n_stations += 1
    print(f"  {n_stations} pay stations", file=sys.stderr)

    out.append("\ncommit;")

    SQL_OUT.parent.mkdir(parents=True, exist_ok=True)
    SQL_OUT.write_text("\n".join(out) + "\n")
    print(f"Wrote {SQL_OUT} ({len(out)} statements)", file=sys.stderr)

    STATIONS_OUT.write_text(json.dumps(
        {"type": "FeatureCollection", "features": stations}, indent=1
    ))
    print(f"Wrote {STATIONS_OUT} ({len(stations)} stations)", file=sys.stderr)


if __name__ == "__main__":
    main()
