/**
 * PSBA IT Inventory - AI Assistant backend, as a Cloudflare Worker.
 *
 * This is the same service the Firebase Cloud Function used to be, moved to a
 * host with a genuinely free plan and no billing account. Cloud Functions are
 * not offered on Firebase's free Spark plan, and Gemini's own free tier needs
 * no card, so the only thing standing between this app and a no-cost
 * assistant was where the code ran.
 *
 * What did NOT change in the move:
 *
 *   - The Gemini API key lives only in the platform's secret store. It is
 *     never in the app, the APK, the web bundle or the repository.
 *   - The only inventory data Gemini sees is the caller's own
 *     permission-scoped facts, built in the app and passed straight through.
 *     Gemini has no database access of any kind.
 *   - Every answer, and every change Gemini thinks was asked for, is still
 *     re-resolved and re-checked by ActionPlanner in the app and still sits
 *     behind the Confirm button. Nothing this Worker returns can cause a
 *     write.
 *   - The security chain runs in the same order: signed in, email verified,
 *     App Check, input caps, per-account daily cap, timeout.
 *
 * What did change: there is no Admin SDK here, so the caller's identity is
 * established by verifying Firebase's own signed tokens against Google's
 * public keys (see verify.js), and the request counter lives in a Durable
 * Object rather than in Firestore. No Firestore data or rules are touched by
 * this Worker at all.
 */
import { buildMessages, normaliseReply, parseJsonObject } from './assistant_prompt.js';
import { selectModel, callModel } from './gemini.js';
import { appCheckRequired } from './usage_policy.js';
import {
  ID_TOKEN_JWKS,
  APP_CHECK_JWKS,
  verifyToken,
  checkIdTokenClaims,
  checkAppCheckClaims,
} from './verify.js';

export { UsageCounter } from './usage_counter.js';

const MAX_QUESTION = 500;
const MAX_GROUNDED = 4000;
const MAX_FACTS_BYTES = 60000;
const MAX_HISTORY = 6;

/**
 * How long Gemini itself is given.
 *
 * The innermost of the deadlines, each of which must strictly exceed the one
 * inside it, or a good answer is thrown away after the account has already
 * been charged a request for it: Gemini 15s, then the app's own 25s.
 */
const TIMEOUT_MS = 15000;

/** Refusals, in the shape the app already understands. */
function refuse(status, code, message, extra = {}) {
  return new Response(JSON.stringify({ error: { code, message, ...extra } }), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

function ok(payload) {
  return new Response(JSON.stringify(payload), {
    headers: { 'content-type': 'application/json' },
  });
}

export default {
  async fetch(request, env) {
    if (request.method !== 'POST') {
      return refuse(405, 'invalid-argument', 'Use POST.');
    }

    const projectId = env.FIREBASE_PROJECT_ID;
    const projectNumber = env.FIREBASE_PROJECT_NUMBER;

    if (!projectId || !projectNumber || !env.GEMINI_API_KEY) {
      console.error('The Worker is not configured', {
        hasProjectId: Boolean(projectId),
        hasProjectNumber: Boolean(projectNumber),
        hasKey: Boolean(env.GEMINI_API_KEY),
      });
      return refuse(503, 'unavailable', 'The assistant is not configured yet.');
    }

    const now = Date.now();

    // ---------------------------------------------------------------- who
    // Only signed-in accounts may spend the allowance, and only verified
    // ones - the same bar firestore.rules sets for reading any inventory.
    const authorization = request.headers.get('authorization') || '';
    const idToken = authorization.toLowerCase().startsWith('bearer ')
      ? authorization.slice(7).trim()
      : '';

    if (!idToken) {
      return refuse(401, 'unauthenticated', 'Sign in to use the assistant.');
    }

    const identity = await verifyToken(idToken, {
      jwksUrl: ID_TOKEN_JWKS,
      checkClaims: (payload, ctx) => checkIdTokenClaims(payload, { ...ctx, projectId }),
      now,
    });

    if (!identity.ok) {
      console.warn('Rejected a caller', { reason: identity.reason });
      return refuse(401, 'unauthenticated', 'Sign in to use the assistant.');
    }

    if (!identity.emailVerified) {
      return refuse(403, 'permission-denied', 'Verify your email address first.');
    }

    // ------------------------------------------------------------ what app
    // App Check: the call must come from a genuine build of this app, not
    // from a script replaying a stolen ID token.
    if (appCheckRequired(env)) {
      const appCheckToken = request.headers.get('x-firebase-appcheck') || '';

      const app = appCheckToken
        ? await verifyToken(appCheckToken, {
            jwksUrl: APP_CHECK_JWKS,
            checkClaims: (payload, ctx) =>
              checkAppCheckClaims(payload, { ...ctx, projectNumber }),
            now,
          })
        : { ok: false, reason: 'missing' };

      if (!app.ok) {
        console.warn('Rejected a call without App Check', {
          uid: identity.uid,
          reason: app.reason,
        });
        return refuse(
          400,
          'failed-precondition',
          'This request did not come from a recognised app installation.',
        );
      }
    }

    // --------------------------------------------------------------- what
    let data;
    try {
      data = await request.json();
    } catch {
      return refuse(400, 'invalid-argument', 'A question is required.');
    }

    // `request.json()` succeeds on a body of literal `null`, and on a number,
    // a string or an array. Only an object has the fields read below, and
    // reading them off `null` would throw past this refusal and become a 500.
    if (!data || typeof data !== 'object' || Array.isArray(data)) {
      return refuse(400, 'invalid-argument', 'A question is required.');
    }

    const question = typeof data.question === 'string' ? data.question.trim() : '';
    const grounded =
      typeof data.groundedAnswer === 'string' ? data.groundedAnswer.slice(0, MAX_GROUNDED) : '';

    // The facts arrive already serialised. They are the largest thing in the
    // request and the Worker has no reason to look inside them, so they are
    // never parsed here: that keeps the whole request well inside the free
    // plan's CPU budget, which excludes time spent waiting on the network but
    // not time spent parsing JSON.
    const factsJson = typeof data.facts === 'string' ? data.facts : '';

    const history = Array.isArray(data.history) ? data.history.slice(-MAX_HISTORY) : [];

    const capabilities = Array.isArray(data.capabilities)
      ? data.capabilities.filter((c) => typeof c === 'string').slice(0, 20).map((c) => c.slice(0, 40))
      : [];

    if (!question) {
      return refuse(400, 'invalid-argument', 'A question is required.');
    }
    if (question.length > MAX_QUESTION) {
      return refuse(400, 'invalid-argument', 'That question is too long.');
    }
    if (!factsJson) {
      return refuse(400, 'invalid-argument', 'Inventory facts are required.');
    }
    // Bytes, not UTF-16 code units: an inventory written in Urdu script is
    // about three bytes per character.
    if (new TextEncoder().encode(factsJson).length > MAX_FACTS_BYTES) {
      return refuse(400, 'invalid-argument', 'Too much data for one question.');
    }

    // ------------------------------------------------------------- how much
    // Counted only once the request is known to be well formed, so a broken
    // client cannot burn somebody's daily allowance on rejected calls.
    let quota;
    try {
      const counter = env.USAGE.get(env.USAGE.idFromName(identity.uid));
      const decision = await counter.fetch('https://usage/count', {
        method: 'POST',
        body: JSON.stringify({ now }),
      });
      quota = await decision.json();
    } catch (error) {
      // No counter means no way to bound the shared free-tier quota, so the
      // call stops here. The app falls back to the answer it computed itself.
      console.error('Usage counter unavailable', {
        message: String(error && error.message).slice(0, 300),
      });
      return refuse(503, 'unavailable', 'The assistant is busy. Please try again.');
    }

    if (!quota.allowed) {
      return refuse(
        429,
        'resource-exhausted',
        quota.reason === 'daily_cap'
          ? `You have reached today's limit of ${quota.limit} assistant questions.`
          : 'Please wait a moment before asking again.',
        { reason: quota.reason, retryAfterSeconds: quota.retryAfterSeconds },
      );
    }

    // ------------------------------------------------------------------ ask
    const { model } = selectModel(env);

    const { system, messages } = buildMessages({
      question,
      groundedAnswer: grounded,
      facts: factsJson,
      history,
      capabilities,
      maxHistory: MAX_HISTORY,
    });

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);

    try {
      const result = await callModel({
        model,
        apiKey: env.GEMINI_API_KEY,
        system,
        messages,
        signal: controller.signal,
      });

      // A cut-off reply could drop the part that carried the real figure, so
      // the app is told to keep its own computed answer instead.
      if (result.truncated) {
        console.warn('Discarded an incomplete reply');
        return refuse(503, 'unavailable', 'The reply was incomplete.');
      }

      const raw = result.raw || parseJsonObject(result.text);
      const reply = normaliseReply(raw);

      if (!reply) {
        return refuse(503, 'unavailable', 'The assistant returned nothing.');
      }

      return ok({
        text: reply.text,
        intent: reply.intent,
        needsClarification: reply.needsClarification,
        model,
        provider: 'gemini',
      });
    } catch (error) {
      // Status and a short message only: an error body can echo request
      // content straight back into the logs, and the key is scrubbed because
      // a transport-level failure is not ours to make promises about.
      const detail = String(error && error.message).slice(0, 300);

      console.error('Assistant error', {
        status: error && error.status,
        message: detail.split(env.GEMINI_API_KEY).join('[redacted]'),
      });

      return refuse(503, 'unavailable', 'The assistant could not be reached.');
    } finally {
      clearTimeout(timer);
    }
  },
};
