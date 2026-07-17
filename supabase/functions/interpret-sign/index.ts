// interpret-sign — the camera-fallback "commodity layer": takes a photo of a
// parking sign and returns a structured plain-English verdict via Claude's
// vision capability. The Anthropic API key stays server-side; the app only
// holds the Supabase anon key.
//
// Deploy:  supabase functions deploy interpret-sign --no-verify-jwt
//          (the app authenticates with the publishable key via the apikey
//          header; publishable keys aren't JWTs, so JWT verification is off)
// Env:     supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//
// Request:  { image_base64, media_type, local_time?, timezone? }
// Response: { can_park_now, level, summary, restrictions, confidence }

import Anthropic from "npm:@anthropic-ai/sdk";

const anthropic = new Anthropic({ apiKey: Deno.env.get("ANTHROPIC_API_KEY") });

const VERDICT_SCHEMA = {
  type: "object",
  properties: {
    can_park_now: {
      type: "boolean",
      description: "Whether a typical private car may legally park here at the given local time",
    },
    level: {
      type: "string",
      enum: ["green", "yellow", "red", "unknown"],
      description: "green = legal, yellow = legal with a condition (paid/time limit), red = do not park, unknown = sign unreadable",
    },
    summary: {
      type: "string",
      description: "One plain-English sentence a driver can absorb in two seconds",
    },
    restrictions: {
      type: "array",
      items: { type: "string" },
      description: "Each posted restriction, one short phrase each",
    },
    confidence: { type: "string", enum: ["high", "medium", "low"] },
  },
  required: ["can_park_now", "level", "summary", "restrictions", "confidence"],
  additionalProperties: false,
} as const;

const SYSTEM_PROMPT = `You interpret street parking signs for a driver who needs an instant answer.
Rules:
- Answer for the specific local time provided, not in general.
- If multiple signs stack, combine them the way an enforcement officer would.
- If the sign is partially unreadable or ambiguous, say so and use level "unknown" with low confidence — never guess confidently.
- Keep the summary to one sentence in plain language ("You can park here until 6 pm, but you have to pay at the kiosk").

Halifax (HRM) local conventions:
- Loading zones are active 8 am–6 pm unless the sign says 24H — outside those hours they are ordinary legal parking.
- Paid zones (A–J) run weekdays 8 am–6 pm, plus Saturdays 8 am–6 pm starting July 18, 2026.
- The overnight winter parking ban (1–6 am, declared ad hoc in winter) is not posted on signs — do not assume it; mention it only if a sign references it.`;

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json({ error: "POST only" }, { status: 405 });
  }

  let body: { image_base64?: string; media_type?: string; local_time?: string; timezone?: string };
  try {
    body = await req.json();
  } catch {
    return Response.json({ error: "invalid JSON body" }, { status: 400 });
  }
  const { image_base64, media_type, local_time, timezone } = body;
  if (!image_base64 || !media_type) {
    return Response.json({ error: "image_base64 and media_type are required" }, { status: 400 });
  }

  const timeContext = local_time
    ? `The current local time is ${local_time} (${timezone ?? "America/Halifax"}).`
    : `Assume the current time in America/Halifax.`;

  try {
    const response = await anthropic.messages.create({
      model: "claude-opus-4-8",
      max_tokens: 2048,
      thinking: { type: "adaptive" },
      system: SYSTEM_PROMPT,
      output_config: { format: { type: "json_schema", schema: VERDICT_SCHEMA } },
      messages: [
        {
          role: "user",
          content: [
            {
              type: "image",
              source: { type: "base64", media_type: media_type as "image/jpeg", data: image_base64 },
            },
            {
              type: "text",
              text: `${timeContext} Can I park where this sign applies, right now?`,
            },
          ],
        },
      ],
    });

    if (response.stop_reason === "refusal") {
      return Response.json(
        {
          can_park_now: false,
          level: "unknown",
          summary: "Couldn't interpret this image — check the posted sign.",
          restrictions: [],
          confidence: "low",
        },
      );
    }

    const text = response.content.find((block) => block.type === "text");
    if (!text || text.type !== "text") {
      return Response.json({ error: "no text in model response" }, { status: 502 });
    }
    // output_config.format guarantees the text block is valid JSON matching the schema.
    return new Response(text.text, { headers: { "Content-Type": "application/json" } });
  } catch (err) {
    console.error("interpret-sign failed:", err);
    return Response.json({ error: "sign interpretation failed" }, { status: 502 });
  }
});
