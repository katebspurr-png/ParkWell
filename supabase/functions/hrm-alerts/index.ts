// hrm-alerts — polls HRM's Service Updates page and flips winter_ban_status
// when the overnight winter parking ban is declared or lifted.
//
// Source of truth (verified 2026-07-17): the Service Updates page carries an
// explicit status line, e.g.
//   "Status: The overnight winter parking ban WILL NOT BE ENFORCED in
//    Zone 1 – Central and Zone 2 – Non-Central."
// When declared, HRM's published scenarios use "WILL BE ENFORCED" /
// "is being enforced" / "has been lifted" per zone, so we parse both zones
// independently. Ban facts: season Dec 15 – Mar 31, hours 1–6 a.m., enforced
// only during declared weather events.
//
// Deploy:  supabase functions deploy hrm-alerts --no-verify-jwt
// Run on a schedule (~every 30 min in winter). Env: SUPABASE_URL,
// SUPABASE_SERVICE_ROLE_KEY (both injected by Supabase).

const SOURCES = [
  "https://www.halifax.ca/transportation/cycling-walking/service-updates",
  "https://www.halifax.ca/transportation/winter-operations/service-updates",
];

// halifax.ca returns 403 to non-browser user agents.
const USER_AGENT =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36";

function stripTags(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/\s+/g, " ");
}

interface ZoneStatus {
  zone1: boolean;
  zone2: boolean;
}

/// Parse the "Status:" line(s) about the parking ban. Returns null when no
/// confident signal is found — the caller then writes nothing.
export function parseZoneStatus(text: string): ZoneStatus | null {
  const statusChunks = [...text.matchAll(/Status:\s*(.*?)(?=Status:|Notifications:|Impact to|$)/gis)]
    .map((m) => m[1])
    .filter((s) => /parking ban/i.test(s));
  if (statusChunks.length === 0) return null;

  const zones: ZoneStatus = { zone1: false, zone2: false };
  let sawSignal = false;

  // Split into clauses so "lifted in Zone 1, but will continue to be
  // enforced in Zone 2" assigns opposite values to each zone.
  const clauses = statusChunks.join(" . ").split(/(?<=[.;])|\bbut\b/i);
  for (const clause of clauses) {
    const mentionsZ1 = /zone\s*1/i.test(clause);
    const mentionsZ2 = /zone\s*2/i.test(clause);
    if (!mentionsZ1 && !mentionsZ2) continue;

    let enforced: boolean | null = null;
    if (/will not be enforced|not being enforced|has been lifted|is lifted/i.test(clause)) {
      enforced = false;
    } else if (/will be enforced|is being enforced|continue to be enforced|remains? in effect/i.test(clause)) {
      enforced = true;
    }
    if (enforced === null) continue;

    sawSignal = true;
    if (mentionsZ1) zones.zone1 = enforced;
    if (mentionsZ2) zones.zone2 = enforced;
  }
  return sawSignal ? zones : null;
}

function banMessage(zones: ZoneStatus): string | null {
  if (zones.zone1 && zones.zone2) {
    return "Overnight winter parking ban enforced tonight, 1–6 a.m., in Zone 1 (Central) and Zone 2 (Non-Central).";
  }
  if (zones.zone1) {
    return "Overnight winter parking ban enforced tonight, 1–6 a.m., in Zone 1 – Central (Halifax Peninsula & downtown Dartmouth).";
  }
  if (zones.zone2) {
    return "Overnight winter parking ban enforced tonight, 1–6 a.m., in Zone 2 – Non-Central.";
  }
  return null;
}

async function checkBanStatus(): Promise<{ zones: ZoneStatus; sourceUrl: string } | null> {
  for (const url of SOURCES) {
    try {
      const res = await fetch(url, { headers: { "User-Agent": USER_AGENT } });
      if (!res.ok) continue;
      const zones = parseZoneStatus(stripTags(await res.text()));
      if (zones !== null) return { zones, sourceUrl: url };
    } catch (_err) {
      // Try the next source; an unreachable page must not flip the flag.
    }
  }
  return null;
}

Deno.serve(async (_req) => {
  const status = await checkBanStatus();
  if (status === null) {
    // Deliberately no write: stale-but-honest beats confidently wrong; the
    // client surfaces staleness via its own fetch timestamps.
    return Response.json({ updated: false, reason: "no confident status line found" });
  }

  const { zones, sourceUrl } = status;
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const res = await fetch(`${supabaseUrl}/rest/v1/winter_ban_status?id=eq.1`, {
    method: "PATCH",
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
      Prefer: "return=minimal",
    },
    body: JSON.stringify({
      active: zones.zone1 || zones.zone2,
      zone1_active: zones.zone1,
      zone2_active: zones.zone2,
      message: banMessage(zones),
      source_url: sourceUrl,
      updated_at: new Date().toISOString(),
    }),
  });

  if (!res.ok) {
    return Response.json({ updated: false, error: await res.text() }, { status: 500 });
  }
  return Response.json({ updated: true, ...zones, source: sourceUrl });
});
