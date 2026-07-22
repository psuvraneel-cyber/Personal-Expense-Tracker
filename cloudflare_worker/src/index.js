let cachedJwks = null;
let cachedJwksExpiry = 0;

function base64UrlDecode(str) {
  let base64 = str.replace(/-/g, "+").replace(/_/g, "/");
  while (base64.length % 4) base64 += "=";
  try {
    return atob(base64);
  } catch (e) {
    throw new Error("Invalid base64 encoding");
  }
}

async function getGoogleJwks() {
  const now = Date.now();
  if (cachedJwks && now < cachedJwksExpiry) {
    return cachedJwks;
  }
  const jwksUrl = "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";
  const res = await fetch(jwksUrl);
  if (!res.ok) {
    throw new Error("Failed to fetch public keys from Google");
  }
  const data = await res.json();
  cachedJwks = data.keys || [];
  cachedJwksExpiry = now + 3600 * 1000;
  return cachedJwks;
}

async function verifyFirebaseIdToken(idToken, projectId) {
  if (!idToken) throw new Error("Token is empty");
  const parts = idToken.split(".");
  if (parts.length !== 3) throw new Error("Malformed token format");

  const [headerB64, payloadB64, signatureB64] = parts;

  let header, payload;
  try {
    header = JSON.parse(base64UrlDecode(headerB64));
    payload = JSON.parse(base64UrlDecode(payloadB64));
  } catch (e) {
    throw new Error("Failed to parse token header or payload");
  }

  // 1. Verify header alg
  if (header.alg !== "RS256") {
    throw new Error("Unsupported signature algorithm");
  }

  // 2. Verify header kid
  if (!header.kid) {
    throw new Error("Missing key identifier");
  }

  // 3. Verify exp (expiration)
  const nowSec = Math.floor(Date.now() / 1000);
  if (!payload.exp || payload.exp <= nowSec) {
    throw new Error("Token has expired");
  }

  // 4. Verify iat (issued at)
  if (!payload.iat || payload.iat > nowSec + 300) { // 5 min clock skew tolerance
    throw new Error("Token issued in the future");
  }

  // 5. Verify aud (audience)
  if (payload.aud !== projectId) {
    throw new Error("Invalid audience claim");
  }

  // 6. Verify iss (issuer)
  if (payload.iss !== `https://securetoken.google.com/${projectId}`) {
    throw new Error("Invalid issuer claim");
  }

  // 7. Verify sub (subject / UID)
  if (!payload.sub || typeof payload.sub !== "string" || payload.sub.trim() === "") {
    throw new Error("Missing or invalid subject claim");
  }

  // 8. Cryptographic Signature Verification
  const keys = await getGoogleJwks();
  const jwk = keys.find(k => k.kid === header.kid);
  if (!jwk) {
    throw new Error("Unknown key identifier");
  }

  // Import public key
  let cryptoKey;
  try {
    cryptoKey = await crypto.subtle.importKey(
      "jwk",
      jwk,
      {
        name: "RSASSA-PKCS1-v1_5",
        hash: "SHA-256",
      },
      false,
      ["verify"]
    );
  } catch (e) {
    throw new Error("Failed to import public key");
  }

  // Decode signature to Uint8Array
  const signatureRaw = base64UrlDecode(signatureB64);
  const signatureBuffer = new Uint8Array(signatureRaw.length);
  for (let i = 0; i < signatureRaw.length; i++) {
    signatureBuffer[i] = signatureRaw.charCodeAt(i);
  }

  const encoder = new TextEncoder();
  const dataBuffer = encoder.encode(`${headerB64}.${payloadB64}`);

  const signatureValid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    signatureBuffer,
    dataBuffer
  );

  if (!signatureValid) {
    throw new Error("Invalid cryptographic signature");
  }

  return payload.sub;
}

async function isUserPremium(uid, revenueCatApiKey) {
  try {
    const res = await fetch(`https://api.revenuecat.com/v1/subscribers/${uid}`, {
      method: "GET",
      headers: {
        "Authorization": `Bearer ${revenueCatApiKey}`,
        "Content-Type": "application/json"
      }
    });
    if (!res.ok) {
      console.error(`RevenueCat error status: ${res.status}`);
      return false;
    }
    const data = await res.json();
    const entitlement = data.subscriber?.entitlements?.["P.E.T Premium"];
    if (!entitlement) return false;

    if (entitlement.expires_date) {
      const expires = Date.parse(entitlement.expires_date);
      if (isNaN(expires) || expires < Date.now()) {
        return false;
      }
    }
    return true;
  } catch (e) {
    console.error(`Failed to verify RevenueCat entitlement: ${e.message}`);
    return false;
  }
}

export default {
  async fetch(request, env, ctx) {
    const startTime = Date.now();
    const requestId = crypto.randomUUID();

    // ── 1. Rejects unsupported HTTP methods ──────────────────────────────────
    if (request.method !== "POST") {
      return new Response(JSON.stringify({ error: "Method not allowed" }), {
        status: 405,
        headers: { "Content-Type": "application/json" }
      });
    }

    // ── 2. Validate Content-Type: application/json ─────────────────────────
    const contentType = request.headers.get("Content-Type") || "";
    if (!contentType.toLowerCase().startsWith("application/json")) {
      return new Response(JSON.stringify({ error: "Invalid Content-Type: Expected application/json" }), {
        status: 400,
        headers: { "Content-Type": "application/json" }
      });
    }

    // ── 3. Verify Authorization Header ───────────────────────────────────────
    const authHeader = request.headers.get("Authorization") || "";
    if (!authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Unauthorized: Missing or invalid token format" }), {
        status: 401,
        headers: { "Content-Type": "application/json" }
      });
    }

    const idToken = authHeader.replace("Bearer ", "").trim();
    if (!idToken) {
      return new Response(JSON.stringify({ error: "Unauthorized: Token is empty" }), {
        status: 401,
        headers: { "Content-Type": "application/json" }
      });
    }

    // ── 4. Validate request body size (max 50 KB) ────────────────────────────
    const contentLengthStr = request.headers.get("Content-Length");
    if (contentLengthStr) {
      const contentLength = parseInt(contentLengthStr, 10);
      if (isNaN(contentLength) || contentLength > 50 * 1024) {
        return new Response(JSON.stringify({ error: "Payload too large: Content-Length exceeds limit" }), {
          status: 413,
          headers: { "Content-Type": "application/json" }
        });
      }
    }

    const rawBody = await request.text();
    if (rawBody.length > 50 * 1024) {
      return new Response(JSON.stringify({ error: "Payload too large: Body exceeds limit" }), {
        status: 413,
        headers: { "Content-Type": "application/json" }
      });
    }

    // ── 5. Parse request JSON ────────────────────────────────────────────────
    let body;
    try {
      body = JSON.parse(rawBody);
    } catch {
      return new Response(JSON.stringify({ error: "Malformed JSON" }), {
        status: 400,
        headers: { "Content-Type": "application/json" }
      });
    }

    // ── 6. Validate Firebase ID Token locally ────────────────────────────────
    const projectId = env.FIREBASE_PROJECT_ID || "personal-expense-tracker-6891b";
    let uid;
    try {
      uid = await verifyFirebaseIdToken(idToken, projectId);
    } catch (err) {
      return new Response(JSON.stringify({ error: `Unauthorized: ${err.message}` }), {
        status: 401,
        headers: { "Content-Type": "application/json" }
      });
    }

    // Generate a secure hashed UID for logging purposes (privacy safety)
    const encoder = new TextEncoder();
    const uidData = encoder.encode(uid);
    const hashBuffer = await crypto.subtle.digest("SHA-256", uidData);
    const hashedUid = Array.from(new Uint8Array(hashBuffer))
      .map(b => b.toString(16).padStart(2, "0"))
      .join("");

    // ── 6.5. Verify Premium Entitlement via RevenueCat ──────────────────────
    const rcApiKey = env.REVENUECAT_API_KEY;
    if (!rcApiKey) {
      return new Response(JSON.stringify({ error: "Server error: Missing RevenueCat API configuration" }), {
        status: 500,
        headers: { "Content-Type": "application/json" }
      });
    }

    const premium = await isUserPremium(uid, rcApiKey);
    if (!premium) {
      logRequest(requestId, hashedUid, 403, Date.now() - startTime, "premium_required");
      return new Response(JSON.stringify({ error: "Forbidden: AI Copilot is a Premium-only feature" }), {
        status: 403,
        headers: { "Content-Type": "application/json" }
      });
    }

    // ── 7. Server-Side Rate Limiting (persistent via KV) ───────────────────
    if (!env.KV_LIMITS) {
      return new Response(JSON.stringify({ error: "Server error: Missing KV_LIMITS binding" }), {
        status: 500,
        headers: { "Content-Type": "application/json" }
      });
    }

    const nowMs = Date.now();
    const minBucket = Math.floor(nowMs / 60000);
    const hrBucket = Math.floor(nowMs / 3600000);
    const dayBucket = Math.floor(nowMs / 86400000);

    const minKey = `limit:${uid}:min:${minBucket}`;
    const hrKey = `limit:${uid}:hr:${hrBucket}`;
    const dayKey = `limit:${uid}:day:${dayBucket}`;

    let minVal, hrVal, dayVal;
    try {
      [minVal, hrVal, dayVal] = await Promise.all([
        env.KV_LIMITS.get(minKey),
        env.KV_LIMITS.get(hrKey),
        env.KV_LIMITS.get(dayKey)
      ]);
    } catch (e) {
      return new Response(JSON.stringify({ error: "Storage service unavailable" }), {
        status: 502,
        headers: { "Content-Type": "application/json" }
      });
    }

    const minCount = minVal ? parseInt(minVal, 10) : 0;
    const hrCount = hrVal ? parseInt(hrVal, 10) : 0;
    const dayCount = dayVal ? parseInt(dayVal, 10) : 0;

    // Burst limit: 10 requests per minute
    if (minCount >= 10) {
      logRequest(requestId, hashedUid, 429, Date.now() - startTime, "burst_limit_exceeded");
      return new Response(
        JSON.stringify({ error: "Rate limit exceeded: Too many requests per minute. Please try again shortly." }),
        {
          status: 429,
          headers: {
            "Content-Type": "application/json",
            "Retry-After": "60"
          }
        }
      );
    }

    // Hourly limit: 50 requests per hour
    if (hrCount >= 50) {
      logRequest(requestId, hashedUid, 429, Date.now() - startTime, "hourly_limit_exceeded");
      return new Response(
        JSON.stringify({ error: "Rate limit exceeded: Hourly quota exceeded. Please try again later." }),
        {
          status: 429,
          headers: {
            "Content-Type": "application/json",
            "Retry-After": "1800"
          }
        }
      );
    }

    // Daily limit: 200 requests per day
    if (dayCount >= 200) {
      logRequest(requestId, hashedUid, 429, Date.now() - startTime, "daily_limit_exceeded");
      return new Response(
        JSON.stringify({ error: "Rate limit exceeded: Daily quota reached. Please try again tomorrow." }),
        {
          status: 429,
          headers: {
            "Content-Type": "application/json",
            "Retry-After": "86400"
          }
        }
      );
    }

    // Update KV counts (expirations are in seconds)
    try {
      await Promise.all([
        env.KV_LIMITS.put(minKey, (minCount + 1).toString(), { expirationTtl: 120 }),
        env.KV_LIMITS.put(hrKey, (hrCount + 1).toString(), { expirationTtl: 7200 }),
        env.KV_LIMITS.put(dayKey, (dayCount + 1).toString(), { expirationTtl: 172800 })
      ]);
    } catch (e) {
      return new Response(JSON.stringify({ error: "Storage update failed" }), {
        status: 502,
        headers: { "Content-Type": "application/json" }
      });
    }

    // ── 8. Request Body Structure Validation ──────────────────────────────────
    // Reject empty message arrays
    if (!body.messages || !Array.isArray(body.messages) || body.messages.length === 0) {
      logRequest(requestId, hashedUid, 400, Date.now() - startTime, "empty_messages");
      return new Response(JSON.stringify({ error: "Bad request: messages must be a non-empty array" }), {
        status: 400,
        headers: { "Content-Type": "application/json" }
      });
    }

    // Reject message count > 20
    if (body.messages.length > 20) {
      logRequest(requestId, hashedUid, 400, Date.now() - startTime, "too_many_messages");
      return new Response(JSON.stringify({ error: "Bad request: messages list cannot exceed 20 messages" }), {
        status: 400,
        headers: { "Content-Type": "application/json" }
      });
    }

    // Reject unsupported modes
    if (body.mode !== undefined) {
      const allowedModes = ["chat", "analysis"];
      if (!allowedModes.includes(body.mode)) {
        logRequest(requestId, hashedUid, 400, Date.now() - startTime, "unsupported_mode");
        return new Response(JSON.stringify({ error: "Bad request: unsupported Copilot mode" }), {
          status: 400,
          headers: { "Content-Type": "application/json" }
        });
      }
    }

    // Validate each message structure, role, type, and bounds
    let totalChars = 0;
    const allowedRoles = ["system", "user", "assistant"];
    for (const msg of body.messages) {
      if (typeof msg !== "object" || msg === null) {
        logRequest(requestId, hashedUid, 400, Date.now() - startTime, "malformed_message_object");
        return new Response(JSON.stringify({ error: "Bad request: messages list must contain valid JSON objects" }), {
          status: 400,
          headers: { "Content-Type": "application/json" }
        });
      }

      // Check key constraints (no deeply nested unexpected keys or extra data)
      const keys = Object.keys(msg);
      if (!keys.includes("role") || !keys.includes("content") || keys.length > 2) {
        logRequest(requestId, hashedUid, 400, Date.now() - startTime, "invalid_message_keys");
        return new Response(JSON.stringify({ error: "Bad request: message objects must only contain role and content fields" }), {
          status: 400,
          headers: { "Content-Type": "application/json" }
        });
      }

      if (typeof msg.role !== "string" || !allowedRoles.includes(msg.role)) {
        logRequest(requestId, hashedUid, 400, Date.now() - startTime, "unsupported_role");
        return new Response(JSON.stringify({ error: "Bad request: unsupported message role" }), {
          status: 400,
          headers: { "Content-Type": "application/json" }
        });
      }

      if (typeof msg.content !== "string") {
        logRequest(requestId, hashedUid, 400, Date.now() - startTime, "malformed_content_type");
        return new Response(JSON.stringify({ error: "Bad request: message content must be a string" }), {
          status: 400,
          headers: { "Content-Type": "application/json" }
        });
      }

      // Max characters per individual message (5,000)
      if (msg.content.length > 5000) {
        logRequest(requestId, hashedUid, 400, Date.now() - startTime, "message_too_long");
        return new Response(JSON.stringify({ error: "Bad request: message exceeds 5,000 characters limit" }), {
          status: 400,
          headers: { "Content-Type": "application/json" }
        });
      }

      totalChars += msg.content.length;
    }

    // Max characters across all messages (20,000)
    if (totalChars > 20000) {
      logRequest(requestId, hashedUid, 400, Date.now() - startTime, "total_messages_too_long");
      return new Response(JSON.stringify({ error: "Bad request: total conversation length exceeds 20,000 characters" }), {
        status: 400,
        headers: { "Content-Type": "application/json" }
      });
    }

    // ── 9. Server-Controlled Model & Token Budgets ─────────────────────────────
    const DEFAULT_MODEL = "llama-3.3-70b-versatile";
    const ALLOWED_MODELS = ["llama-3.3-70b-versatile", "llama-3-8b-8192", "mixtral-8x7b-32768"];
    const MAX_OUTPUT_TOKENS = 600;

    let targetModel = DEFAULT_MODEL;
    if (body.model && ALLOWED_MODELS.includes(body.model)) {
      targetModel = body.model;
    }

    let targetMaxTokens = 400;
    if (body.max_tokens && typeof body.max_tokens === "number") {
      targetMaxTokens = Math.min(body.max_tokens, MAX_OUTPUT_TOKENS);
    }

    // ── 10. Forward to Groq (with Upstream Error Handling and Timeouts) ──────────
    if (!env.GROQ_API_KEY) {
      logRequest(requestId, hashedUid, 500, Date.now() - startTime, "missing_groq_api_key");
      return new Response(JSON.stringify({ error: "Server error: Missing AI provider configuration" }), {
        status: 500,
        headers: { "Content-Type": "application/json" }
      });
    }

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 15000); // 15-second upstream timeout

    let groqResp;
    try {
      groqResp = await fetch("https://api.groq.com/openai/v1/chat/completions", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${env.GROQ_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: targetModel,
          messages: body.messages,
          max_tokens: targetMaxTokens,
          temperature: 0.5, // Server-controlled fixed temperature
        }),
        signal: controller.signal
      });
    } catch (err) {
      if (err.name === "AbortError") {
        logRequest(requestId, hashedUid, 504, Date.now() - startTime, "upstream_timeout");
        return new Response(JSON.stringify({ error: "AI gateway timeout: Upstream provider took too long to respond." }), {
          status: 504,
          headers: { "Content-Type": "application/json" }
        });
      }
      logRequest(requestId, hashedUid, 502, Date.now() - startTime, `upstream_fetch_error: ${err.message}`);
      return new Response(JSON.stringify({ error: "AI gateway error: Failed to connect to upstream provider." }), {
        status: 502,
        headers: { "Content-Type": "application/json" }
      });
    } finally {
      clearTimeout(timeoutId);
    }

    // ── 11. Upstream Response Parsing & Sanitization ───────────────────────────
    if (!groqResp.ok) {
      const errStatus = groqResp.status;
      logRequest(requestId, hashedUid, 502, Date.now() - startTime, `upstream_returned_${errStatus}`);
      
      // Map upstream 429 specifically to 503 Service Unavailable (so client doesn't retry client-side errors)
      if (errStatus === 429) {
        return new Response(JSON.stringify({ error: "AI service temporarily overloaded. Please try again shortly." }), {
          status: 503,
          headers: { "Content-Type": "application/json" }
        });
      }

      return new Response(JSON.stringify({ error: "AI service failed: Upstream provider returned an error." }), {
        status: 502,
        headers: { "Content-Type": "application/json" }
      });
    }

    let groqData;
    try {
      groqData = await groqResp.json();
    } catch {
      logRequest(requestId, hashedUid, 502, Date.now() - startTime, "malformed_upstream_json");
      return new Response(JSON.stringify({ error: "AI service error: Received invalid response format from upstream." }), {
        status: 502,
        headers: { "Content-Type": "application/json" }
      });
    }

    // Verify response structure containing choice content
    const choiceContent = groqData?.choices?.[0]?.message?.content;
    if (typeof choiceContent !== "string") {
      logRequest(requestId, hashedUid, 502, Date.now() - startTime, "invalid_choice_content_structure");
      return new Response(JSON.stringify({ error: "AI service error: Empty or invalid completion generated." }), {
        status: 502,
        headers: { "Content-Type": "application/json" }
      });
    }

    // Clean choices to only return what is safe and necessary (sanitize and strip unused metadata)
    const sanitizedResp = {
      choices: [
        {
          message: {
            role: "assistant",
            content: choiceContent
          }
        }
      ]
    };

    logRequest(requestId, hashedUid, 200, Date.now() - startTime, "success");

    return new Response(JSON.stringify(sanitizedResp), {
      status: 200,
      headers: { "Content-Type": "application/json" }
    });
  },
};

// ── Minimal, Structured Production Logging (Privacy Safe) ─────────────────────
function logRequest(requestId, hashedUid, status, latencyMs, statusCategory) {
  const logMsg = {
    timestamp: new Date().toISOString(),
    requestId,
    userHash: hashedUid,
    status,
    latencyMs,
    category: statusCategory
  };
  console.log(JSON.stringify(logMsg));
}
