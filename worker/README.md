# AI Assistant backend — Cloudflare Worker

The server side of the PSBA IT Inventory AI Assistant. It holds the Gemini API
key, builds the grounded prompt, and answers the app.

It is a Cloudflare Worker rather than a Firebase Cloud Function for one
reason: **Cloud Functions are not offered on Firebase's free Spark plan**, so
deploying one would mean enabling Blaze and putting a card on file. The
Workers free plan and the Gemini API free tier both need no billing account at
all, so this path costs nothing and asks for no payment method.

Nothing about the security model changed in the move — see "How a request is
trusted" below.

## What it costs

| | Free allowance | What happens past it |
|---|---|---|
| Cloudflare Workers | 100,000 requests/day, 10 ms CPU per request | Requests fail; nothing is billed |
| Durable Objects (SQLite) | 100,000 writes/day, 5 GB stored | Writes fail; nothing is billed |
| Gemini API | Flash models listed free of charge, subject to per-minute and per-day request limits | Requests are refused; nothing is billed |

No credit card is involved at any point. Cloudflare only asks for one if you
choose to exceed the free allowance, and the Gemini free tier only moves to a
paid tier if you link a billing account yourself.

## Deploying

```bash
cd worker
npm install -g wrangler          # or use npx wrangler for everything below
npx wrangler login               # opens a browser; no card requested

# The Gemini key. Get one from https://aistudio.google.com/apikey
# It is stored by Cloudflare and never appears in this repository.
npx wrangler secret put GEMINI_API_KEY

npx wrangler deploy
```

`wrangler deploy` prints the URL, e.g.
`https://psba-inventory-assistant.<your-subdomain>.workers.dev`.

Then build the app against it. Both defines are required — the assistant stays
on its offline engine unless it is told it may call out *and* where to:

```bash
flutter build apk --release \
  --dart-define=AI_LLM_ENABLED=true \
  --dart-define=AI_PROXY_URL=https://psba-inventory-assistant.<subdomain>.workers.dev
```

### Side-loading the APK

App Check's Play Integrity provider only issues tokens for builds installed
from Google Play, so a side-loaded APK cannot produce one and every call would
be refused. While testing that way, set `AI_REQUIRE_APP_CHECK = "false"` in
`wrangler.toml` and redeploy. The Worker still requires a signed-in,
email-verified account and still applies the per-account daily cap. Put it
back to `"true"` before the app goes to Play.

## How a request is trusted

The Worker has no Admin SDK and no privileged access to the Firebase project,
so it earns its trust by verifying Firebase's own signed tokens against
Google's public keys — both documented for exactly this, "non-Google custom
backend resources, like your own self-hosted backend".

1. **Who** — the `Authorization: Bearer <Firebase ID token>` header is
   verified: RS256, a `kid` from Google's key set, `aud` equal to this project
   id, `iss` equal to `https://securetoken.google.com/<project id>`, and the
   timestamps in the right direction. Then `email_verified` must be true, the
   same bar `firestore.rules` sets for reading any inventory at all.
2. **What app** — the `X-Firebase-AppCheck` header is verified the same way
   against Firebase App Check's JWKS, pinned to this project's number.
3. **What was asked** — the question, facts and history are length-capped, and
   the facts are passed through untouched.
4. **How much** — one Durable Object per account counts the request against
   the daily cap, using the same `usage_policy.js` the Cloud Function used.
   A Durable Object handles its requests one at a time, which gives the same
   atomicity the Firestore transaction used to.
5. **Ask Gemini** — 15 second deadline, and the reply must arrive through the
   single declared function so it is structured rather than prose.

The endpoint is publicly reachable, which buys an attacker nothing: without a
valid, unexpired, correctly-scoped Firebase ID token it answers nobody.

## What it is still not allowed to do

Gemini sees only the caller's own permission-scoped inventory facts, built in
the app. It has no database access. Any change it believes was asked for comes
back as a *suggestion*, which `ActionPlanner` in the app re-resolves and
re-checks from scratch against the same snapshot before the user is shown a
Confirm button. Nothing this Worker returns can cause a write.

## Tests

```bash
cd worker && npm test
```

No network is used: the Gemini request builder and response reader are pure,
and the token tests mint real RS256 tokens with a real key pair and serve a
real JWK set from a stubbed `fetch`, so the signature check is genuinely
exercised — including forgery attempts.
