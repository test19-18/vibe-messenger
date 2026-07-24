// Supabase Edge Function: send-call-push
// Sends a VoIP/call push notification to a callee's registered devices.
//
// Firebase credentials are planned as a server secret (FIREBASE_SERVICE_ACCOUNT_JSON
// or similar). Until Firebase is configured, this function returns a clear
// "backend-ready" response indicating the push was queued but not delivered.
// It does NOT fake a successful delivery.
//
// POST /functions/v1/send-call-push
// Headers: Authorization: Bearer <user_access_token>
// Body: {
//   "callId": "<uuid>",
//   "calleeId": "<uuid>",
//   "roomName": "<string>",
//   "callerName": "<string>",
//   "mediaKind": "audio" | "video"
// }
//
// Environment variables:
//   SUPABASE_URL              — project URL
//   SUPABASE_SERVICE_ROLE_KEY — service-role key (standard name)
//   SUPABASE_SERVICE_KEY      — legacy alias, accepted as fallback
//   SUPABASE_ANON_KEY         — anon/publishable key
//   FIREBASE_*                — Firebase service account (optional)

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

interface CallDevice {
  id: string;
  platform: string;
  fcm_token: string;
  voip_token: string | null;
  device_name: string | null;
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

  // Authenticate the user (caller)
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

  // Parse body
  let body: {
    callId?: string;
    calleeId?: string;
    roomName?: string;
    callerName?: string;
    callerId?: string;
    mediaKind?: string;
    conversationId?: string;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const callId = body.callId;
  const calleeId = body.calleeId;
  const roomName = body.roomName;
  const callerName = body.callerName ?? "Unknown";
  const callerId = body.callerId ?? user.id;
  const mediaKind = body.mediaKind === "video" ? "video" : "audio";
  const conversationId = body.conversationId ?? null;

  if (!callId || !calleeId || !roomName) {
    return json({ error: "callId, calleeId, and roomName are required" }, 400);
  }

  // Verify the caller matches the authenticated user
  const serviceClient = createClient(supabaseUrl, serviceKey);

  const { data: call } = await serviceClient
    .from("calls")
    .select("caller_id, callee_id, state")
    .eq("id", callId)
    .maybeSingle();

  if (!call) {
    return json({ error: "Call not found" }, 404);
  }

  if (call.caller_id !== user.id) {
    return json({ error: "Only the caller can send call push" }, 403);
  }

  if (call.callee_id !== calleeId) {
    return json({ error: "calleeId does not match call record" }, 400);
  }

  // Fetch callee's registered call devices (active only)
  const { data: devices, error: deviceError } = await serviceClient
    .from("call_devices")
    .select("id, platform, fcm_token, voip_token, device_name")
    .eq("user_id", calleeId)
    .is("disabled_at", null)
    .order("last_seen_at", { ascending: false })
    .limit(5) as { data: CallDevice[] | null; error: typeof deviceError };

  if (deviceError) {
    console.error("Device lookup error:", deviceError);
    return json({ error: "Failed to fetch callee devices" }, 500);
  }

  if (!devices || devices.length === 0) {
    return json({
      delivered: false,
      reason: "no_devices",
      message: "Callee has no registered call devices. Push not sent.",
      deviceCount: 0,
    }, 200);
  }

  // Build the push payload — data-only message so the client retains full
  // control over UI presentation and call lifecycle. The `type` field
  // identifies the payload contract the client parses.
  const pushPayload = {
    call_id: callId,
    room_name: roomName,
    caller_name: callerName,
    caller_id: callerId,
    media_kind: mediaKind,
    type: "incoming_call",
    ...(conversationId ? { conversation_id: conversationId } : {}),
  };

  // Check if Firebase is configured
  // Firebase service account JSON should be stored as a server secret.
  // Supported env var names (in order of preference):
  //   FIREBASE_SERVICE_ACCOUNT_JSON  — raw JSON string
  //   FIREBASE_PROJECT_ID + FIREBASE_CLIENT_EMAIL + FIREBASE_PRIVATE_KEY  — split fields
  const firebaseJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  const firebaseProjectId = Deno.env.get("FIREBASE_PROJECT_ID");

  const firebaseConfigured = !!(firebaseJson || firebaseProjectId);

  if (!firebaseConfigured) {
    // Firebase is not yet configured. Return a clear "backend-ready" response
    // rather than faking delivery. The caller knows push was not sent.
    return json({
      delivered: false,
      reason: "firebase_not_configured",
      message:
        "Push notification backend is ready but Firebase is not configured. " +
        "Set FIREBASE_SERVICE_ACCOUNT_JSON (or FIREBASE_PROJECT_ID, " +
        "FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY) to enable delivery. " +
        "The callee will not receive a push notification until Firebase is configured.",
      deviceCount: devices.length,
      payload: pushPayload,
    }, 200);
  }

  // Firebase IS configured — attempt delivery via FCM v1 HTTP API.
  // This path requires a valid service account to obtain an OAuth2 access token.
  // The implementation below uses the FCM v1 HTTP API endpoint.
  try {
    let serviceAccount: { project_id?: string; client_email?: string; private_key?: string };

    if (firebaseJson) {
      serviceAccount = JSON.parse(firebaseJson);
    } else {
      serviceAccount = {
        project_id: firebaseProjectId,
        client_email: Deno.env.get("FIREBASE_CLIENT_EMAIL"),
        private_key: Deno.env.get("FIREBASE_PRIVATE_KEY")?.replace(/\\n/g, "\n"),
      };
    }

    if (!serviceAccount.project_id || !serviceAccount.client_email || !serviceAccount.private_key) {
      return json({
        delivered: false,
        reason: "firebase_incomplete",
        message: "Firebase service account is incomplete. Check FIREBASE_* env vars.",
        deviceCount: devices.length,
      }, 200);
    }

    // Obtain an OAuth2 access token using the service account JWT
    // (RFC 7523 JWT Bearer Grant flow against Google's token endpoint)
    const now = Math.floor(Date.now() / 1000);
    const assertionHeader = { alg: "RS256", typ: "JWT" };
    const assertionPayload = {
      iss: serviceAccount.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      exp: now + 3600,
      iat: now,
    };

    // Import the private key
    const pemContents = serviceAccount.private_key
      .replace("-----BEGIN PRIVATE KEY-----", "")
      .replace("-----END PRIVATE KEY-----", "")
      .replace(/\s+/g, "");
    const pemBytes = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));

    const cryptoKey = await crypto.subtle.importKey(
      "pkcs8",
      pemBytes,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["sign"]
    );

    const encoder = new TextEncoder();
    const headerB64 = btoa(JSON.stringify(assertionHeader))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    const payloadB64 = btoa(JSON.stringify(assertionPayload))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    const signingInput = `${headerB64}.${payloadB64}`;
    const signature = await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      cryptoKey,
      encoder.encode(signingInput)
    );
    const signatureB64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    const assertion = `${headerB64}.${payloadB64}.${signatureB64}`;

    // Exchange the assertion for an access token
    const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion,
      }),
    });

    if (!tokenResponse.ok) {
      const errText = await tokenResponse.text();
      console.error("FCM token exchange failed:", errText);
      return json({
        delivered: false,
        reason: "firebase_auth_failed",
        message: "Failed to authenticate with Firebase.",
        deviceCount: devices.length,
      }, 500);
    }

    const tokenData = await tokenResponse.json();
    const accessToken = tokenData.access_token;

    // Send FCM v1 messages to each device
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`;
    const results: Array<{ deviceId: string; success: boolean; error?: string }> = [];

    for (const device of devices!) {
      const message = {
        message: {
          token: device.fcm_token,
          data: {
            call_id: callId,
            room_name: roomName,
            caller_name: callerName,
            caller_id: callerId,
            media_kind: mediaKind,
            type: "incoming_call",
            ...(conversationId ? { conversation_id: conversationId } : {}),
          },
          android: {
            priority: "high",
            notification: {
              title: `Incoming ${mediaKind} call`,
              body: `${callerName} is calling`,
              click_action: "CALL_INVITE",
              channel_id: "vibe_incoming_calls",
            },
          },
          apns: {
            headers: { "apns-priority": "10" },
            payload: {
              aps: {
                "content-available": true,
                "alert": {
                  title: `Incoming ${mediaKind} call`,
                  body: `${callerName} is calling`,
                },
                "interruption-level": "time-sensitive",
              },
            },
          },
        },
      };

      try {
        const fcmResponse = await fetch(fcmUrl, {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify(message),
        });

        if (fcmResponse.ok) {
          results.push({ deviceId: device.id, success: true });
        } else {
          const errText = await fcmResponse.text();
          results.push({ deviceId: device.id, success: false, error: errText });
          // If the token is invalid, disable the device
          if (fcmResponse.status === 404 || fcmResponse.status === 400) {
            await serviceClient
              .from("call_devices")
              .update({ disabled_at: new Date().toISOString() })
              .eq("id", device.id);
          }
        }
      } catch (err) {
        results.push({
          deviceId: device.id,
          success: false,
          error: err instanceof Error ? err.message : "Unknown error",
        });
      }
    }

    const successCount = results.filter((r) => r.success).length;

    return json({
      delivered: successCount > 0,
      deviceCount: devices!.length,
      successCount,
      results,
    }, 200);
  } catch (err) {
    console.error("Firebase push error:", err);
    return json({
      delivered: false,
      reason: "firebase_delivery_error",
      message: err instanceof Error ? err.message : "Unknown error",
      deviceCount: devices!.length,
    }, 500);
  }
});
