/**
 * Tests for the Worker's request handler, end to end and without a network.
 *
 * A real RS256 key pair mints real ID tokens, a stubbed `fetch` serves both
 * the JWK set and Gemini, and a stand-in Durable Object serves the quota
 * decision - so this exercises the actual security chain in order rather than
 * any one piece of it: signed in, email verified, well-formed body, quota,
 * Gemini, reply.
 *
 * Run with: npm test --prefix worker   (or: node --test worker/test/)
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import worker from '../src/index.js';
import { resetKeyCache, ID_TOKEN_JWKS } from '../src/verify.js';

const PROJECT_ID = 'it-inventory-8e690';
const PROJECT_NUMBER = '315288299970';
const ENDPOINT = 'https://assistant.example.workers.dev/';

const ALGORITHM = { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' };

const toBase64Url = (bytes) =>
  Buffer.from(bytes).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

const encodeSegment = (value) => toBase64Url(new TextEncoder().encode(JSON.stringify(value)));

let signingKey;
let jwks;

async function keys() {
  if (signingKey) return { signingKey, jwks };

  const pair = await crypto.subtle.generateKey(
    { ...ALGORITHM, modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]) },
    true,
    ['sign', 'verify'],
  );

  const jwk = await crypto.subtle.exportKey('jwk', pair.publicKey);

  signingKey = pair.privateKey;
  jwks = { keys: [{ ...jwk, kid: 'handler-key', alg: 'RS256', use: 'sig' }] };

  return { signingKey, jwks };
}

/** A genuine, currently-valid Firebase ID token for this project. */
async function idToken(overrides = {}) {
  const { signingKey: key } = await keys();
  const seconds = Math.floor(Date.now() / 1000);

  const payload = {
    aud: PROJECT_ID,
    iss: `https://securetoken.google.com/${PROJECT_ID}`,
    sub: 'uid-handler',
    email: 'admin@psba.test',
    email_verified: true,
    auth_time: seconds - 60,
    iat: seconds - 30,
    exp: seconds + 3600,
    ...overrides,
  };

  const signed = `${encodeSegment({ alg: 'RS256', kid: 'handler-key' })}.${encodeSegment(payload)}`;
  const signature = await crypto.subtle.sign(ALGORITHM, key, new TextEncoder().encode(signed));

  return `${signed}.${toBase64Url(new Uint8Array(signature))}`;
}

/** What Gemini answers with, unless a test says otherwise. */
const GEMINI_REPLY = {
  candidates: [
    {
      finishReason: 'STOP',
      content: {
        parts: [
          {
            functionCall: {
              name: 'reply',
              args: { answer: 'Township Bazaar mein 47 units hain.', needsClarification: false },
            },
          },
        ],
      },
    },
  ],
};

const realFetch = globalThis.fetch;

/** Serves the key set and Gemini, and records what Gemini was sent. */
function stubNetwork({ gemini = GEMINI_REPLY } = {}) {
  const sent = [];

  globalThis.fetch = async (url, init) => {
    const target = String(url);

    if (target === ID_TOKEN_JWKS) {
      return { ok: true, json: async () => jwks };
    }

    if (target.includes('generativelanguage.googleapis.com')) {
      sent.push({ url: target, init });
      return { ok: true, json: async () => gemini };
    }

    throw new Error(`unexpected fetch to ${target}`);
  };

  return sent;
}

/** A stand-in for the USAGE Durable Object binding. */
function usage(decision = { allowed: true, used: 1, limit: 60 }) {
  return {
    idFromName: (name) => ({ name }),
    get: () => ({
      fetch: async () =>
        new Response(JSON.stringify(decision), {
          headers: { 'content-type': 'application/json' },
        }),
    }),
  };
}

const env = (overrides = {}) => ({
  FIREBASE_PROJECT_ID: PROJECT_ID,
  FIREBASE_PROJECT_NUMBER: PROJECT_NUMBER,
  GEMINI_API_KEY: 'test-key-not-a-real-one',
  AI_MODEL: 'gemini-3.6-flash',
  // App Check is exercised in verify.test.js; switching it off here keeps
  // these tests about the handler's own ordering.
  AI_REQUIRE_APP_CHECK: 'false',
  USAGE: usage(),
  ...overrides,
});

/** Posts a raw body string with a valid token unless told otherwise. */
async function post(body, { token = 'valid', environment = env() } = {}) {
  const headers = { 'content-type': 'application/json' };

  if (token === 'valid') headers.authorization = `Bearer ${await idToken()}`;
  else if (token) headers.authorization = `Bearer ${token}`;

  return worker.fetch(new Request(ENDPOINT, { method: 'POST', headers, body }), environment);
}

const goodBody = (overrides = {}) =>
  JSON.stringify({
    question: 'Township Bazaar mein kitne laptop hain?',
    facts: JSON.stringify({ totals: { totalQuantity: 125 } }),
    groundedAnswer: '',
    history: [],
    capabilities: ['sendToBazaar'],
    ...overrides,
  });

test.beforeEach(async () => {
  await keys();
  resetKeyCache();
  stubNetwork();
});

test.afterEach(() => {
  globalThis.fetch = realFetch;
  resetKeyCache();
});

// ===========================================================================
// THE HAPPY PATH
// ===========================================================================

test('a signed-in, verified caller gets a grounded answer', async () => {
  const response = await post(goodBody());

  assert.equal(response.status, 200);

  const body = await response.json();
  assert.equal(body.text, 'Township Bazaar mein 47 units hain.');
  assert.equal(body.provider, 'gemini');
  assert.equal(body.model, 'gemini-3.6-flash');
  assert.equal(body.intent, null);
});

test('the key travels as a header and never in the URL', async () => {
  const sent = stubNetwork();
  await post(goodBody());

  assert.equal(sent.length, 1);
  assert.equal(sent[0].url.includes('test-key-not-a-real-one'), false);
  assert.equal(sent[0].init.headers['x-goog-api-key'], 'test-key-not-a-real-one');
});

// ===========================================================================
// MALFORMED BODIES - none of them may become a 500
// ===========================================================================

test('a body of literal null is refused, not thrown past', async () => {
  // request.json() SUCCEEDS on `null`, so the fields read after it would be
  // read off null and throw - which Cloudflare would turn into a 500 for an
  // authenticated caller.
  const response = await post('null');

  assert.equal(response.status, 400);
  assert.equal((await response.json()).error.code, 'invalid-argument');
});

test('a body that is not an object at all is refused', async () => {
  for (const body of ['3', '"a string"', '[1,2]', 'true']) {
    const response = await post(body);
    assert.equal(response.status, 400, body);
  }
});

test('a body that is not JSON is refused', async () => {
  const response = await post('<html>502 Bad Gateway</html>');
  assert.equal(response.status, 400);
});

test('a missing question, or missing facts, is refused', async () => {
  assert.equal((await post(JSON.stringify({ facts: '{}' }))).status, 400);
  assert.equal((await post(goodBody({ question: '   ' }))).status, 400);
  assert.equal((await post(goodBody({ facts: '' }))).status, 400);
});

test('an over-long question is refused', async () => {
  const response = await post(goodBody({ question: 'x'.repeat(501) }));
  assert.equal(response.status, 400);
});

// ===========================================================================
// THE SECURITY CHAIN, IN ORDER
// ===========================================================================

test('no Authorization header is refused before anything else', async () => {
  const response = await worker.fetch(
    new Request(ENDPOINT, { method: 'POST', body: goodBody() }),
    env(),
  );

  assert.equal(response.status, 401);
});

test('a garbage bearer token is refused', async () => {
  const response = await post(goodBody(), { token: 'not.a.token' });
  assert.equal(response.status, 401);
});

test('an unverified email address is refused', async () => {
  const token = await idToken({ email_verified: false });
  const response = await post(goodBody(), { token });

  assert.equal(response.status, 403);
  assert.equal((await response.json()).error.code, 'permission-denied');
});

test('App Check is demanded when it is switched on', async () => {
  const response = await post(goodBody(), {
    environment: env({ AI_REQUIRE_APP_CHECK: 'true' }),
  });

  assert.equal(response.status, 400);
  assert.equal((await response.json()).error.code, 'failed-precondition');
});

test('a spent daily allowance is reported as such', async () => {
  const response = await post(goodBody(), {
    environment: env({
      USAGE: usage({ allowed: false, reason: 'daily_cap', limit: 60, retryAfterSeconds: 3600 }),
    }),
  });

  assert.equal(response.status, 429);

  const body = await response.json();
  assert.equal(body.error.code, 'resource-exhausted');
  assert.match(body.error.message, /limit of 60/);
});

test('a counter that cannot be reached fails closed', async () => {
  const broken = env({
    USAGE: {
      idFromName: () => ({}),
      get: () => ({ fetch: async () => { throw new Error('unreachable'); } }),
    },
  });

  const response = await post(goodBody(), { environment: broken });
  assert.equal(response.status, 503);
});

test('an unconfigured Worker refuses rather than calling out', async () => {
  for (const missing of ['FIREBASE_PROJECT_ID', 'FIREBASE_PROJECT_NUMBER', 'GEMINI_API_KEY']) {
    const response = await post(goodBody(), { environment: env({ [missing]: undefined }) });
    assert.equal(response.status, 503, missing);
  }
});

test('anything but POST is refused', async () => {
  for (const method of ['GET', 'PUT', 'DELETE', 'OPTIONS']) {
    const response = await worker.fetch(new Request(ENDPOINT, { method }), env());
    assert.equal(response.status, 405, method);
  }
});

// ===========================================================================
// WHAT GEMINI SENDS BACK
// ===========================================================================

test('a truncated reply is discarded rather than half-shown', async () => {
  stubNetwork({
    gemini: {
      candidates: [
        {
          finishReason: 'MAX_TOKENS',
          content: { parts: [{ functionCall: { name: 'reply', args: { answer: 'half an ans' } } }] },
        },
      ],
    },
  });

  const response = await post(goodBody());
  assert.equal(response.status, 503);
});

test('a reply with nothing usable in it is discarded', async () => {
  stubNetwork({ gemini: { candidates: [] } });

  const response = await post(goodBody());
  assert.equal(response.status, 503);
});

test('an invented action is stripped before it ever reaches the app', async () => {
  stubNetwork({
    gemini: {
      candidates: [
        {
          finishReason: 'STOP',
          content: {
            parts: [
              {
                functionCall: {
                  name: 'reply',
                  args: {
                    answer: 'Done.',
                    action: { kind: 'deleteAllAssets', assetRef: 'IT-LAP-001' },
                  },
                },
              },
            ],
          },
        },
      ],
    },
  });

  const response = await post(goodBody());

  assert.equal(response.status, 200);
  assert.equal((await response.json()).intent, null);
});
