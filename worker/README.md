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
| Gemini API | Flash models free of charge, but see the daily cap below | Requests are refused; nothing is billed |

No credit card is involved at any point. Cloudflare only asks for one if you
choose to exceed the free allowance, and the Gemini free tier only moves to a
paid tier if you link a billing account yourself.

### The Gemini daily cap is the real limit

Cloudflare's 100,000 requests a day are not the constraint. Gemini's free tier
is, and it is much smaller than it looks. The allowance is counted **per model
per day** — `GenerateRequestsPerDayPerProjectPerModel-FreeTier` — and measured
on 2026-09-27:

| Model | Free requests per day | Notes |
|---|---|---|
| `gemini-3.6-flash` | **20** | Accurate, but 20 questions and the assistant goes quiet |
| `gemini-3.8-flash` | **20** | Most accurate of the three in testing |
| `gemini-3.5-flash-lite` | comfortably more (26+ in one run, no refusal) | **Configured default** |

Past the cap Gemini answers `429 RESOURCE_EXHAUSTED`. The Worker now reports
that as `resource-exhausted` with a "wait a minute and ask again" message
rather than "could not be reached", so it does not look like a network fault.

Because the allowance is per model, switching `AI_MODEL` gives a **separate**
allowance rather than a share of the same one. Check your own numbers at
<https://ai.dev/rate-limit>.

The trade-off behind the default: on a question the app's own engine does not
recognise, Lite is weaker at reasoning over several records at once — asked
about printers at Head Office, where 8 are working and 8 are damaged, it
reported only the damaged ones. Given the same question **with** the app's
computed answer attached, which is what the app sends whenever its on-device
engine understands the question, Lite answered correctly. If you would rather
have the stronger model and accept 20 questions a day, set
`AI_MODEL = "gemini-3.8-flash"`.

## Running it locally (no Cloudflare account)

This is the fastest way to get real Gemini answers, and the only setup step
that needs anything from you is the API key. `wrangler dev` runs the Worker on
this machine — no Cloudflare login, no deploy, no card.

```bash
cd worker
cp .dev.vars.example .dev.vars
# then paste your key into .dev.vars - get one free at
# https://aistudio.google.com/apikey
npx wrangler dev            # serves http://127.0.0.1:8787
```

`.dev.vars` is git-ignored, so the key stays on this machine and never reaches
the repository or the app. It also sets `AI_REQUIRE_APP_CHECK=false`, which is
required for local testing: App Check's Play Integrity provider issues tokens
only to Play-installed builds, so a debug build on an emulator cannot produce
one and every call would otherwise be refused. The Worker still demands a
signed-in, email-verified Firebase account and still applies the daily cap.

Then run the app against it. On an Android emulator the host's loopback is
`10.0.2.2`, not `127.0.0.1`:

```bash
flutter run -d emulator-5554 \
  --dart-define=AI_LLM_ENABLED=true \
  --dart-define=AI_PROXY_URL=http://10.0.2.2:8787
```

Both defines are required. With either missing the assistant stays on its
on-device engine, and the app now says so in the log:
`AI assistant: AI_LLM_ENABLED is false, so the on-device engine answers.`

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
