// Supabase Edge Function: issue-livekit-token
// Issues a LiveKit access token (JWT) for a call participant.
//
// The token is signed with LIVEKIT_API_SECRET and contains a VideoGrant
// that allows the participant to join the call room with publish/subscribe
// permissions. The token is never stored or logged.
//
// LiveKit credentials come ONLY from environment variables:
//   LIVEKIT_URL         — LiveKit Cloud server URL (e.g. wss://your-project.livekit.cloud)
//   LIVEKIT_API_KEY     — LiveKit API key
//   LIVEKIT_API_SECRET  — LiveKit API secret (used to sign the JWT, never sent to client)
//
// Supabase credentials:
//   SUPABASE_URL              — project URL
//   SUPABASE_SERVICE_ROLE_KEY — service-role key (standard name)
//   SUPABASE_SERVICE_KEY      — legacy alias, accepted as fallback
//   SUPABASE_ANON_KEY         — anon/publishable key
//
// POST /functions/v1/issue-livekit-token
// Headers: Authorization: Bearer <user_access_token>
// Body: { "callId": "<uuid>", "roomName": "<string>" }
// Response: { "token": "<jwt>", "url": "<livekit_url>" }

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

// ---------------------------------------------------------------------------
// LiveKit JWT generation (HS256)
//
// LiveKit access tokens are standard JWTs signed with the API secret using
// HMAC-SHA256. The payload includes:
//   iss  — API key (issuer)
//   sub  — participant identity (subject)
//   exp  — expiration time
//   nbf  — not-before time
//   video — VideoGrant object { room, roomJoin, canPublish, canSubscribe, ... }
//
// This implementation uses the Web Crypto API available in Deno to compute
// the HMAC-SHA256 signature. No external JWT library is required, which keeps
// the function self-contained and avoids dependency on npm registries.
// ---------------------------------------------------------------------------

const encoder = new TextEncoder();

function base64UrlEncode(data: ArrayBuffer | Uint8Array): string {
  const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function base64UrlEncodeString(str: string): string {
  return base64UrlEncode(encoder.encode(str));
}

async function hmacSha256(key: string, message: string): Promise<ArrayBuffer> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    encoder.encode(key),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  return crypto.subtle.sign("HMAC", cryptoKey, encoder.encode(message));
}

interface VideoGrant {
  roomCreate?: boolean;
  roomJoin?: boolean;
  roomList?: boolean;
  roomRecord?: boolean;
  roomAdmin?: boolean;
  room?: string;
  canPublish?: boolean;
  canPublishData?: boolean;
  canSubscribe?: boolean;
  canUpdateOwnMetadata?: boolean;
  hidden?: boolean;
}

interface LiveKitTokenOptions {
  apiKey: string;
  apiSecret: string;
  identity: string;
  roomName: string;
  ttlSeconds?: number;
  grant?: Partial<VideoGrant>;
}

async function createLiveKitToken(opts: LiveKitTokenOptions): Promise<string> {
  const {
    apiKey,
    apiSecret,
    identity,
    roomName,
    ttlSeconds = 7200, // 2 hours default
    grant = {},
  } = opts;

  const now = Math.floor(Date.now() / 1000);
  const exp = now + ttlSeconds;

  const videoGrant: VideoGrant = {
    roomJoin: true,
    room: roomName,
    canPublish: true,
    canPublishData: true,
    canSubscribe: true,
    canUpdateOwnMetadata: true,
    ...grant,
  };

  const payload = {
    iss: apiKey,
    sub: identity,
    iat: now,
    exp,
    nbf: now,
    video: videoGrant,
  };

  const header = { alg: "HS256", typ: "JWT" };
  const headerB64 = base64UrlEncodeString(JSON.stringify(header));
  const payloadB64 = base64UrlEncodeString(JSON.stringify(payload));
  const signingInput = `${headerB64}.${payloadB64}`;

  const signature = await hmacSha256(apiSecret, signingInput);
  const signatureB64 = base64UrlEncode(signature);

  return `${headerB64}.${payloadB64}.${signatureB64}`;
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  // LiveKit credentials must come ONLY from env
  const livekitUrl = Deno.env.get("LIVEKIT_URL");
  const livekitApiKey = Deno.env.get("LIVEKIT_API_KEY");
  const livekitApiSecret = Deno.env.get("LIVEKIT_API_SECRET");

  if (!livekitUrl || !livekitApiKey || !livekitApiSecret) {
    console.error("Missing LiveKit credentials in environment");
    return json({
      error: "LiveKit is not configured. Set LIVEKIT_URL, LIVEKIT_API_KEY, and LIVEKIT_API_SECRET.",
    }, 503);
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
  let body: { callId?: string; roomName?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const callId = body.callId;
  const roomName = body.roomName;

  if (!callId || !roomName) {
    return json({ error: "callId and roomName are required" }, 400);
  }

  // Validate room name format (alphanumeric + dash/underscore)
  if (!/^[a-zA-Z0-9_\-]+$/.test(roomName)) {
    return json({ error: "Invalid roomName format" }, 400);
  }

  // Service client to verify the call
  const serviceClient = createClient(supabaseUrl, serviceKey);

  // Verify the call exists, the user is a party, and the call is active
  const { data: call, error: callError } = await serviceClient
    .from("calls")
    .select("id, room_name, state, caller_id, callee_id")
    .eq("id", callId)
    .eq("room_name", roomName)
    .in("state", ["created", "ringing", "accepted", "connected"])
    .maybeSingle();

  if (callError) {
    console.error("Call lookup error:", callError);
    return json({ error: "Failed to verify call" }, 500);
  }

  if (!call) {
    return json({ error: "Call not found or not active" }, 404);
  }

  // Verify the user is a party to this call
  if (call.caller_id !== userId && call.callee_id !== userId) {
    return json({ error: "Not authorized for this call" }, 403);
  }

  // Issue the LiveKit token
  // TTL: 2 hours for active calls, but the call itself will expire via DB logic
  try {
    const token = await createLiveKitToken({
      apiKey: livekitApiKey,
      apiSecret: livekitApiSecret,
      identity: userId,
      roomName: roomName,
      ttlSeconds: 7200,
      grant: {
        roomJoin: true,
        room: roomName,
        canPublish: true,
        canPublishData: true,
        canSubscribe: true,
        canUpdateOwnMetadata: true,
      },
    });

    // The LiveKit URL is returned so the client knows where to connect
    // Convert wss:// to https:// for the URL field if needed, but LiveKit
    // client SDKs typically expect the wss:// URL directly
    return json({
      token,
      url: livekitUrl,
    });
  } catch (err) {
    console.error("Token generation error:", err);
    return json({ error: "Failed to generate LiveKit token" }, 500);
  }
});
