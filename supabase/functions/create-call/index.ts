// Supabase Edge Function: create-call
// Creates a 1:1 personal call record and returns call metadata.
// The caller's Flutter client invokes this to initiate a call.
//
// Requires: Supabase service-role key (passed via Authorization header from
// the caller's authenticated session — the function uses the user's JWT to
// identify the caller, then uses the service key for DB writes).
//
// Environment variables (set in Supabase project secrets):
//   SUPABASE_URL              — project URL
//   SUPABASE_SERVICE_ROLE_KEY — service-role key (server only, never in client)
//   SUPABASE_ANON_KEY         — anon/publishable key
//
//   Legacy alias: SUPABASE_SERVICE_KEY is still accepted as a fallback if
//   SUPABASE_SERVICE_ROLE_KEY is not set. New deployments should use the
//   standard SUPABASE_SERVICE_ROLE_KEY name.
//
// POST /functions/v1/create-call
// Headers: Authorization: Bearer <user_access_token>
// Body: {
//   "calleeId": "<uuid>",
//   "mediaKind": "audio" | "video",        // optional, default "audio"
//   "conversationId": "<uuid>" | null      // optional, direct conversation ID
// }
// Response: { "callId": "<uuid>", "roomName": "<string>", "state": "created" }

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

  // Extract the user's JWT from the Authorization header
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return json({ error: "Missing or invalid Authorization header" }, 401);
  }
  const userToken = authHeader.replace("Bearer ", "");

  // Create a client with the user's token to verify auth and get user ID
  const userClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY") ?? "", {
    global: { headers: { Authorization: `Bearer ${userToken}` } },
  });

  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) {
    return json({ error: "Authentication required" }, 401);
  }

  const callerId = user.id;

  // Parse body
  let body: {
    calleeId?: string;
    mediaKind?: string;
    conversationId?: string;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const calleeId = body.calleeId;
  const mediaKind = body.mediaKind === "video" ? "video" : "audio";
  const conversationId = body.conversationId ?? null;

  if (!calleeId) {
    return json({ error: "calleeId is required" }, 400);
  }

  // Validate UUID format
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!uuidRegex.test(calleeId)) {
    return json({ error: "Invalid calleeId format" }, 400);
  }
  if (calleeId === callerId) {
    return json({ error: "Cannot call yourself" }, 400);
  }

  // Validate conversationId if provided (must be a valid UUID)
  if (conversationId !== null) {
    if (!uuidRegex.test(conversationId)) {
      return json({ error: "Invalid conversationId format" }, 400);
    }
  }

  // Service-role client for privileged DB operations
  const serviceClient = createClient(supabaseUrl, serviceKey);

  // 1. Check if caller can call callee (membership + blocks + privacy)
  const { data: canCall, error: canCallError } = await serviceClient.rpc(
    "can_call_user",
    { _caller_id: callerId, _callee_id: calleeId }
  );

  if (canCallError) {
    console.error("can_call_user error:", canCallError);
    return json({ error: "Failed to verify call permission" }, 500);
  }

  if (!canCall) {
    return json({
      error: "Cannot call this user (blocked, not a contact, or privacy settings prevent it)",
    }, 403);
  }

  // 2. Check if callee is already in an active call (busy)
  const { data: isBusy, error: busyError } = await serviceClient.rpc(
    "user_has_active_call",
    { _user_id: calleeId }
  );

  if (busyError) {
    console.error("user_has_active_call error:", busyError);
    return json({ error: "Failed to check callee availability" }, 500);
  }

  if (isBusy) {
    return json({ error: "User is currently in another call", code: "busy" }, 409);
  }

  // Verify conversationId (if provided) is a direct conversation where both
  // caller and callee are the two direct members. This prevents a caller from
  // attaching a call to an unrelated conversation.
  if (conversationId !== null) {
    const { data: conv, error: convError } = await serviceClient
      .from("conversations")
      .select("id, kind, direct_user_low, direct_user_high")
      .eq("id", conversationId)
      .maybeSingle();

    if (convError || !conv) {
      return json({ error: "conversationId not found" }, 400);
    }
    if (conv.kind !== "direct") {
      return json({
        error: "conversationId must reference a direct conversation",
      }, 400);
    }
    const members = new Set([conv.direct_user_low, conv.direct_user_high]);
    if (!members.has(callerId) || !members.has(calleeId)) {
      return json({
        error: "Caller and callee must both be members of the conversation",
      }, 403);
    }
  }

  // 3. Check for existing active call between these users
  const { data: existingCall } = await serviceClient
    .from("calls")
    .select("id, state")
    .or(`and(caller_id.eq.${callerId},callee_id.eq.${calleeId}),and(caller_id.eq.${calleeId},callee_id.eq.${callerId})`)
    .in("state", ["created", "ringing", "accepted", "connected"])
    .limit(1)
    .maybeSingle();

  if (existingCall) {
    return json({
      error: "An active call already exists between these users",
      code: "duplicate",
      callId: existingCall.id,
    }, 409);
  }

  // 4. Generate room name (deterministic, collision-resistant)
  const roomName = `call-${crypto.randomUUID()}`;

  // 5. Create the call record
  const { data: call, error: callError } = await serviceClient
    .from("calls")
    .insert({
      room_name: roomName,
      caller_id: callerId,
      callee_id: calleeId,
      state: "created",
      media_kind: mediaKind,
      conversation_id: conversationId,
    })
    .select("id, room_name, state, conversation_id")
    .single();

  if (callError) {
    console.error("Call creation error:", callError);
    // Check if it's a rate limit error
    if (callError.code === "42901") {
      return json({ error: "Rate limit exceeded. Please wait before making another call." }, 429);
    }
    return json({ error: "Failed to create call" }, 500);
  }

  // 6. Create participant records
  const { error: participantError } = await serviceClient
    .from("call_participants")
    .insert([
      {
        call_id: call.id,
        user_id: callerId,
        direction: "outgoing",
        participant_identity: callerId,
      },
      {
        call_id: call.id,
        user_id: calleeId,
        direction: "incoming",
        participant_identity: calleeId,
      },
    ]);

  if (participantError) {
    console.error("Participant creation error:", participantError);
  }

  // 7. Log the 'created' event
  const { error: eventError } = await serviceClient
    .from("call_events")
    .insert({
      call_id: call.id,
      actor_id: callerId,
      event_type: "created",
      metadata: { media_kind: mediaKind, room_name: roomName },
    });

  if (eventError) {
    console.error("Event log error:", eventError);
  }

  return json({
    callId: call.id,
    roomName: call.room_name,
    state: call.state,
    conversationId: call.conversation_id ?? null,
  });
});
