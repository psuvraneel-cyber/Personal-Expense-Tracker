# P.E.T — Operations runbook

What to do when something needs attention after release. (Not deployed to
Hosting: `firebase.json` ignores `*.md`.)

## Deploy

| What | Command (from the repo root) | Notes |
|---|---|---|
| Firestore rules | `npx firebase-tools@14 deploy --only firestore:rules --project personal-expense-tracker-6891b` | Run `cd firestore_tests && npm test` first |
| Legal pages (`docs/*.html`) | `npx firebase-tools@14 deploy --only hosting --project personal-expense-tracker-6891b` | Then check all three URLs return 200 |
| Worker | `cd cloudflare_worker && npm test && npx wrangler deploy` | First deploy after the Durable Object change applies migration `v1` |
| Worker secret | `cd cloudflare_worker && npx wrangler secret put <NAME>` | `GROQ_API_KEY`, `REVENUECAT_API_KEY`; optional `DELETION_ALERT_WEBHOOK`, `REFERRAL_ID_SALT` |

## Roll back

- **Worker:** `npx wrangler deployments list`, then `npx wrangler rollback <deployment-id>`.
- **Rules:** Firebase console → Firestore → Rules → history → restore the previous version.
- **App:** halt the staged rollout in Play Console; ship a fixed build with a higher version code.

## Account-deletion requests (web form)

Promise in the privacy policy: done within 30 days (usually 48 hours).

1. Alert arrives (if `DELETION_ALERT_WEBHOOK` is set) with a key like `deletion:<time>:<uuid>`.
2. Read it: `npx wrangler kv key get --binding KV_LIMITS "<key>"`. List all open requests with `npx wrangler kv key list --binding KV_LIMITS --prefix deletion:`.
3. **Verify ownership:** email the address and ask the person to reply from it (or to sign in and use Settings → Delete Account). Don't delete data for an unverified address.
4. Delete:
   - in Firebase Auth, find the user by email and note the UID;
   - delete `users/<uid>` and all its sub-collections in Firestore;
   - delete the user's households / memberships;
   - delete the RevenueCat customer;
   - delete the Firebase Auth user;
   - delete the request key: `npx wrangler kv key delete --binding KV_LIMITS "<key>"`.
5. Reply to confirm.

## Rotating secrets

| Secret | Where to rotate | Then |
|---|---|---|
| Groq API key | Groq console → API keys | `npx wrangler secret put GROQ_API_KEY`; revoke the old key |
| RevenueCat secret key | RevenueCat → Project settings → API keys | `npx wrangler secret put REVENUECAT_API_KEY`; revoke the old key |
| Google / Firebase API key | Google Cloud → APIs & Services → Credentials | Firebase client keys are public; keep them restricted to the Android app (package + SHA-1) and Firebase APIs |
| Upload keystore | Play Console → App integrity → upload key reset | Never commit `*.jks` or `key.properties` |

If a secret is ever committed, revoke it first; cleaning Git history comes second.

## App Check (turning it on)

1. Firebase console → App Check → register the Android app with Play Integrity.
2. Put the Android app ID (`mobilesdk_app_id`) in `FIREBASE_APP_IDS` in `wrangler.toml`.
3. Watch App Check metrics for a few days (most requests verified).
4. Set `REQUIRE_APP_CHECK = "true"` and deploy the Worker.
5. Only then consider enforcing App Check on Firestore. Repeated `permission-denied` writes are parked in the app's queue, not lost, but they won't sync until fixed.

## Watching

- **Crashlytics:** new crash clusters after a release.
- **Android vitals:** ANR rate (keep under 0.47%), crash rate.
- **Worker logs** (`npx wrangler tail`): rising `upstream_*`, `free_quota_exhausted` or 5xx categories.
- **Groq console:** spend against the limit.
- **RevenueCat:** failed renewals, refunds.
- **AI reports:** review `users/*/ai_reports` regularly (Play AI-Generated Content policy).
