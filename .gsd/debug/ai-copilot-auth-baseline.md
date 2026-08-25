# AI Copilot Auth 401 — Deep Diagnosis Baseline

**Date:** 2026-08-25  
**Status:** INVESTIGATION COMPLETE — READY FOR REMEDIATION

---

## 1. Exact Observed Failure

**User-visible error:** `"Unauthorized: Invalid Firebase token"`

**Critical observation:** The string `"Invalid Firebase token"` does **NOT** exist anywhere in the current repository source code. The Worker at `cloudflare_worker/src/index.js` line 235 returns:

```
`Unauthorized: ${err.message}`
```

Where `err.message` is one of:
- `Token is empty`
- `Malformed token format`
- `Token has expired`
- `Invalid audience claim`
- `Invalid issuer claim`
- `Unknown key identifier`
- `Invalid cryptographic signature`
- etc.

**None of these produce the exact string `"Invalid Firebase token"`.**

This is the strongest evidence that the **deployed Worker differs from the current repository code.**

---

## 2. Expected Auth Flow

```
Android App
  → FirebaseAuth.instance.currentUser.getIdToken()
  → HTTP POST https://pet-ai-copilot.pet-app.workers.dev
     Authorization: Bearer <Firebase ID Token>
  → Worker verifies token (RS256, kid, exp, iat, aud, iss, sub, signature)
  → Worker checks RevenueCat premium entitlement
  → Worker enforces KV rate limits
  → Worker forwards to Groq with server-controlled system prompt
  → Response returned to client
```

## 3. Actual Auth Flow (Broken)

```
Android App
  → getIdToken() (no forceRefresh, may return cached/stale token)
  → HTTP POST to Worker
  → Worker returns: {"error": "Unauthorized: Invalid Firebase token"}
  → Client catches ClientErrorException(401, msg)
  → NO retry with forceRefresh
  → Error displayed to user
```

---

## 4. Root Cause Hypotheses (Ranked)

### H1: DEPLOYMENT DRIFT — STALE WORKER (95% probability) ⭐ PRIMARY
The deployed Worker at `https://pet-ai-copilot.pet-app.workers.dev` is running an **older version** of `index.js` that:
- Has a different/simpler Firebase verification that returns generic `"Invalid Firebase token"` 
- May not have the detailed `verifyFirebaseIdToken()` function
- May use a different or missing `FIREBASE_PROJECT_ID` env var

**Evidence:**
- The error string `"Invalid Firebase token"` does not exist in current source
- The `wrangler.toml` has `FIREBASE_WEB_API_KEY = "REPLACE_ME"` (not configured)
- No `FIREBASE_PROJECT_ID` is configured in `wrangler.toml` `[vars]`
- The `wrangler.toml` doesn't declare `kv_namespaces` for `KV_LIMITS`
- No deployment history or CI/CD pipeline exists

### H2: MISSING WORKER ENVIRONMENT VARIABLES (80% probability)
Even if the current source were deployed, the Worker would likely fail because:
- `env.FIREBASE_PROJECT_ID` is not set (falls back to hardcoded default)
- `env.REVENUECAT_API_KEY` may not be configured as a secret
- `env.GROQ_API_KEY` may not be configured as a secret
- `KV_LIMITS` namespace binding is not declared in `wrangler.toml`

### H3: CLIENT TOKEN REFRESH FAILURE (60% probability — secondary issue)
The client uses `user.getIdToken()` without `forceRefresh: true`:
- Firebase ID tokens expire after 1 hour
- If cached token is stale, the Worker rejects it
- Client does NOT retry with a fresh token on 401
- `ClientErrorException` is immediately rethrown without retry

### H4: FIREBASE PROJECT ID MISMATCH (30% probability)
The app uses `personal-expense-tracker-6891b`. If the deployed Worker has a different or missing project ID, `aud`/`iss` validation fails.

### H5: JWKS KEY ROTATION (10% probability)
If Google rotated signing keys and the Worker had cached old JWKS, kid lookup would fail. Current code has 1-hour JWKS cache but no key-miss refresh.

---

## 5. Current Worker Verification Logic

Function `verifyFirebaseIdToken(idToken, projectId)` at line 30:
1. Validates JWT structure (3 parts)
2. Parses header and payload
3. Checks `header.alg === "RS256"`
4. Checks `header.kid` exists
5. Checks `payload.exp > now` (not expired)
6. Checks `payload.iat <= now + 300` (not issued in future, 5-min skew)
7. Checks `payload.aud === projectId`
8. Checks `payload.iss === "https://securetoken.google.com/${projectId}"`
9. Checks `payload.sub` is non-empty string
10. Fetches Google JWKS (with 1-hour cache)
11. Finds JWK matching `header.kid`
12. Imports public key and verifies RS256 signature

---

## 6. Client Token Flow

- `ai_copilot_service.dart` line 163: `user.getIdToken()` (no forceRefresh)
- Line 168–181: POST with `Authorization: Bearer $idToken`
- Line 183–191: 4xx → `ClientErrorException(statusCode, errMsg)` → rethrown
- Line 122–131: 4xx errors (`ClientErrorException`) are **never retried**
- Only generic `Exception` (5xx, network) gets one retry after 2s

---

## 7. Known Configuration Issues

| Config Item | Status | Impact |
|---|---|---|
| `wrangler.toml` FIREBASE_PROJECT_ID | NOT SET | Falls back to hardcode |
| `wrangler.toml` FIREBASE_WEB_API_KEY | `REPLACE_ME` | Unused by current code |
| `wrangler.toml` KV_LIMITS binding | NOT DECLARED | Worker returns 500 |
| `wrangler.toml` secrets | Not configured | Needs wrangler secret put |
| Client forceRefresh | Never used | Stale tokens not retried |
| Rate limit: client daily | 150/day | Mismatches server 200/day |
| 401 UI message | Mentions GROQ_API_KEY | Misleading; it's Firebase auth |

---

## 8. Rate Limit Discrepancy

| Limit | Client (`ai_rate_limiter.dart`) | Server (`index.js`) |
|---|---|---|
| Per minute | 10 | 10 |
| Per hour | 50 | 50 |
| **Per day** | **150** ❌ | **200** |

The client UI displays `150/day` but the server allows `200/day`. The server is authoritative — the client must match.
