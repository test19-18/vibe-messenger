// Supabase Edge Function: expire-stale-calls
// Expires calls that have been stuck in 'created' or 'ringing' state beyond
// their timeout thresholds. Intended to be called by a cron scheduler or
// the pg_cron job defined in the migration.
//
// This edge function is an alternative to the pg_cron-based RPC. It can be
// called by an external scheduler (e.g. Supabase scheduled function, GitHub
// Actions cron, or any HTTP cron service) if pg_cron is unavailable.
//
// GET /functions/v1/expire-stale-calls
// or
// POST /functions/v1/expire-stale-calls
//
// No authentication required (uses service key internally), but should be
// protected by Supabase Edge Function secrets or API gateway rules in
// production. Alternatively, pass a CRON_SECRET header for validation.
//
// Environment variables:
//   SUPABASE_URL              — project URL
//   SUPABASE_SERVICE_ROLE_KEY — service-role key (standard name)
//   SUPABASE_SERVICE_KEY      — legacy alias, accepted as fallback
//   CRON_SECRET               — optional protection secret

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Optional CRON_SECRET validation
  const cronSecret = Deno.env.get("CRON_SECRET");
  if (cronSecret) {
    const providedSecret = req.headers.get("X-Cron-Secret");
    if (providedSecret !== cronSecret) {
      return json({ error: "Unauthorized: invalid or missing X-Cron-Secret" }, 401);
    }
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
    Deno.env.get("SUPABASE_SERVICE_KEY");

  if (!supabaseUrl || !serviceKey) {
    return json({
      error:
        "Server misconfigured: missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY (SUPABASE_SERVICE_KEY legacy alias also accepted)",
    }, 500);
  }

  const serviceClient = createClient(supabaseUrl, serviceKey);

  const now = new Date();
  const ringingTimeoutMs = 45 * 1000;  // 45 seconds
  const createdTimeoutMs = 90 * 1000;  // 90 seconds

  const ringingCutoff = new Date(now.getTime() - ringingTimeoutMs);
  const createdCutoff = new Date(now.getTime() - createdTimeoutMs);

  let expiredRinging = 0;
  let expiredCreated = 0;
  const expiredCallIds: string[] = [];

  // 1. Expire calls stuck in 'ringing' beyond timeout
  const { data: staleRinging, error: ringingError } = await serviceClient
    .from("calls")
    .select("id, room_name, caller_id, callee_id")
    .eq("state", "ringing")
    .lt("ringing_at", ringingCutoff.toISOString())
    .limit(200);

  if (ringingError) {
    console.error("Error fetching stale ringing calls:", ringingError);
    return json({ error: "Failed to fetch stale ringing calls" }, 500);
  }

  if (staleRinging && staleRinging.length > 0) {
    for (const call of staleRinging) {
      const { error: updateError } = await serviceClient
        .from("calls")
        .update({
          state: "expired",
          ended_at: now.toISOString(),
          end_reason: "ringing_timeout",
        })
        .eq("id", call.id)
        .eq("state", "ringing"); // Optimistic lock

      if (!updateError) {
        expiredRinging++;
        expiredCallIds.push(call.id);

        // Log the event
        await serviceClient.from("call_events").insert({
          call_id: call.id,
          event_type: "expired",
          metadata: { reason: "ringing_timeout", ringing_at: call.ringing_at },
        });
      }
    }
  }

  // 2. Expire calls stuck in 'created' beyond timeout
  const { data: staleCreated, error: createdError } = await serviceClient
    .from("calls")
    .select("id, room_name, caller_id, callee_id")
    .eq("state", "created")
    .lt("created_at", createdCutoff.toISOString())
    .limit(200);

  if (createdError) {
    console.error("Error fetching stale created calls:", createdError);
    return json({ error: "Failed to fetch stale created calls" }, 500);
  }

  if (staleCreated && staleCreated.length > 0) {
    for (const call of staleCreated) {
      const { error: updateError } = await serviceClient
        .from("calls")
        .update({
          state: "expired",
          ended_at: now.toISOString(),
          end_reason: "created_timeout",
        })
        .eq("id", call.id)
        .eq("state", "created"); // Optimistic lock

      if (!updateError) {
        expiredCreated++;
        expiredCallIds.push(call.id);

        // Log the event
        await serviceClient.from("call_events").insert({
          call_id: call.id,
          event_type: "expired",
          metadata: { reason: "created_timeout" },
        });
      }
    }
  }

  const totalExpired = expiredRinging + expiredCreated;

  return json({
    expired: totalExpired,
    ringingExpired: expiredRinging,
    createdExpired: expiredCreated,
    callIds: expiredCallIds,
    timestamp: now.toISOString(),
  });
});
