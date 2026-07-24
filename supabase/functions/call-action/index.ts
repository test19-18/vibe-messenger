// Supabase Edge Function: call-action
// Handles state transitions for a call: ringing, accepted, connected,
// declined, cancelled, missed, ended, failed.
//
// The function validates that the requesting user is a party to the call
// and that the state transition is valid before applying it.
//
// POST /functions/v1/call-action
// Headers: Authorization: Bearer <user_access_token>
// Body: {
//   "callId": "<uuid>",
//   "action": "ringing" | "accept" | "connect" | "decline" | "cancel" | "end" | "missed" | "fail"
// }
//
// Environment variables:
//   SUPABASE_URL              — project URL
//   SUPABASE_SERVICE_ROLE_KEY — service-role key (standard name)
//   SUPABASE_SERVICE_KEY      — legacy alias, accepted as fallback
//   SUPABASE_ANON_KEY         — anon/publishable key

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// Valid actions and the target state they map to
const ACTION_TO_STATE: Record<string, string> = {
  ringing: "ringing",
  accept: "accepted",
  connect: "connected",
  decline: "declined",
  cancel: "cancelled",
  end: "ended",
  missed: "missed",
  fail: "failed",
};

// Valid state transitions: from → [allowed target states]
const VALID_TRANSITIONS: Record<string, string[]> = {
  created: ["ringing", "cancelled", "expired"],
  ringing: ["accepted", "declined", "cancelled", "missed", "expired"],
  accepted: ["connected", "ended", "failed"],
  connected: ["ended", "failed"],
  declined: [],
  cancelled: [],
  missed: [],
  busy: [],
  ended: [],
  failed: [],
  expired: [],
};

// Which party is allowed to perform each action
const ACTION_PARTY: Record<string, "caller" | "callee" | "either"> = {
  ringing: "caller",
  accept: "callee",
  connect: "either",
  decline: "callee",
  cancel: "caller",
  end: "either",
  missed: "callee",
  fail: "either",
};

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
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

  // Authenticate the user
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return json({ error: "Missing or invalid Authorization header" }, 401);
  }
  const userToken = authHeader.replace("Bearer ", "");

  const userClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY") ?? "", {
    global: { headers: { Authorization: `Bearer ${userToken}` } },
  });

  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) {
    return json({ error: "Authentication required" }, 401);
  }

  const userId = user.id;

  // Parse body
  let body: { callId?: string; action?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const callId = body.callId;
  const action = body.action;

  if (!callId || !action) {
    return json({ error: "callId and action are required" }, 400);
  }

  const targetState = ACTION_TO_STATE[action];
  if (!targetState) {
    return json({
      error: `Invalid action. Must be one of: ${Object.keys(ACTION_TO_STATE).join(", ")}`,
    }, 400);
  }

  // Service client for DB operations
  const serviceClient = createClient(supabaseUrl, serviceKey);

  // Fetch the call
  const { data: call, error: callError } = await serviceClient
    .from("calls")
    .select("id, state, caller_id, callee_id, room_name")
    .eq("id", callId)
    .maybeSingle();

  if (callError) {
    console.error("Call lookup error:", callError);
    return json({ error: "Failed to fetch call" }, 500);
  }

  if (!call) {
    return json({ error: "Call not found" }, 404);
  }

  // Verify the user is a party to this call
  const isCaller = call.caller_id === userId;
  const isCallee = call.callee_id === userId;

  if (!isCaller && !isCallee) {
    return json({ error: "Not authorized for this call" }, 403);
  }

  // Check which party is allowed to perform this action
  const allowedParty = ACTION_PARTY[action];
  if (allowedParty === "caller" && !isCaller) {
    return json({ error: "Only the caller can perform this action" }, 403);
  }
  if (allowedParty === "callee" && !isCallee) {
    return json({ error: "Only the callee can perform this action" }, 403);
  }

  // Validate state transition
  const allowedTargets = VALID_TRANSITIONS[call.state] ?? [];
  if (!allowedTargets.includes(targetState)) {
    return json({
      error: `Cannot transition from '${call.state}' to '${targetState}'`,
      currentState: call.state,
    }, 409);
  }

  // Apply the state transition
  const updateData: Record<string, unknown> = {
    state: targetState,
  };

  // The DB trigger (guard_call_write) handles timestamp and duration calculation
  // We just set the state and let the trigger do the rest

  const { data: updatedCall, error: updateError } = await serviceClient
    .from("calls")
    .update(updateData)
    .eq("id", callId)
    .select("id, state, duration_seconds")
    .single();

  if (updateError) {
    console.error("Call update error:", updateError);
    return json({ error: "Failed to update call state" }, 500);
  }

  // Log the event
  const eventMap: Record<string, string> = {
    ringing: "ringing",
    accept: "accepted",
    connect: "connected",
    decline: "declined",
    cancel: "cancelled",
    end: "ended",
    missed: "missed",
    fail: "failed",
  };

  await serviceClient.from("call_events").insert({
    call_id: callId,
    actor_id: userId,
    event_type: eventMap[action] ?? action,
    metadata: { from_state: call.state, to_state: targetState },
  });

  // Update participant joined_at/left_at for connect/end
  if (action === "connect") {
    await serviceClient
      .from("call_participants")
      .update({ joined_at: new Date().toISOString() })
      .eq("call_id", callId)
      .eq("user_id", userId);
  } else if (action === "end") {
    await serviceClient
      .from("call_participants")
      .update({ left_at: new Date().toISOString() })
      .eq("call_id", callId)
      .is("left_at", null);
  }

  return json({
    callId: updatedCall.id,
    state: updatedCall.state,
    durationSeconds: updatedCall.duration_seconds ?? null,
  });
});
