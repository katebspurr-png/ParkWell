// hrm-alerts — polls HRM's public winter-operations page and flips the
// winter_ban_status row when a winter parking ban is declared or lifted.
//
// This is the dynamic-overlay feed: HRM declares the ban ad hoc based on
// weather (31+ times in a recent season), so it must be polled, not
// hand-maintained. Run on a schedule (e.g. every 30 min via pg_cron +
// pg_net, or an external cron hitting this function's URL).
//
// Deploy:  supabase functions deploy hrm-alerts --no-verify-jwt
// Env:     SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (both injected by Supabase)
//
// ⚠️ The page structure and phrasing below are a best-effort first pass —
// verify against the live page and tighten the patterns before relying on it.

const SOURCES = [
  "https://www.halifax.ca/transportation/winter-operations/winter-parking-ban",
  "https://www.halifax.ca/transportation/winter-operations",
];

// Phrases HRM has used to announce/lift the ban. Checked case-insensitively
// against the page text with tags stripped.
const BAN_ACTIVE_PATTERNS = [
  /winter parking ban (?:is|will be) (?:in effect|enforced)/i,
  /parking ban (?:is|will be) enforced (?:tonight|overnight)/i,
  /overnight parking ban is in effect/i,
];
const BAN_LIFTED_PATTERNS = [
  /(?:is|are) not (?:in effect|being enforced)/i,
  /no winter parking ban/i,
  /parking ban (?:has been|is) lifted/i,
];

function stripTags(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/\s+/g, " ");
}

async function checkBanStatus(): Promise<{ active: boolean; message: string | null; sourceUrl: string } | null> {
  for (const url of SOURCES) {
    try {
      const res = await fetch(url, { headers: { "User-Agent": "ParkWell/0.1 (winter ban monitor)" } });
      if (!res.ok) continue;
      const text = stripTags(await res.text());

      // "Lifted" phrasing wins when both appear (pages often explain the ban
      // in general terms and then state today's status).
      if (BAN_LIFTED_PATTERNS.some((p) => p.test(text))) {
        return { active: false, message: null, sourceUrl: url };
      }
      if (BAN_ACTIVE_PATTERNS.some((p) => p.test(text))) {
        return {
          active: true,
          message: "HRM winter parking ban in effect — vehicles may be ticketed or towed. Check halifax.ca.",
          sourceUrl: url,
        };
      }
    } catch (_err) {
      // Try the next source; an unreachable page must not flip the flag.
    }
  }
  return null; // No confident signal — leave current status untouched.
}

Deno.serve(async (_req) => {
  const status = await checkBanStatus();
  if (status === null) {
    // Deliberately no write: stale-but-honest beats confidently wrong, and
    // the client surfaces staleness via its own fetch timestamps.
    return Response.json({ updated: false, reason: "no confident signal from HRM sources" });
  }

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
      active: status.active,
      message: status.message,
      source_url: status.sourceUrl,
      updated_at: new Date().toISOString(),
    }),
  });

  if (!res.ok) {
    return Response.json({ updated: false, error: await res.text() }, { status: 500 });
  }
  return Response.json({ updated: true, active: status.active, source: status.sourceUrl });
});
