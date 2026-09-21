/**
 * Tests for the part of this Worker that decides whether to trust a caller.
 *
 * There is no Admin SDK here, so everything rests on verifying Firebase's own
 * signed tokens. These tests mint real RS256 tokens with a real key pair and
 * serve a real JWK set from a stubbed fetch, so the signature check is
 * genuinely exercised rather than mocked away - including the ways a forged
 * token tries to get past it.
 *
 * Run with: npm test --prefix worker   (or: node --test worker/test/)
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  decodeJwt,
  checkIdTokenClaims,
  checkAppCheckClaims,
  verifyToken,
  resetKeyCache,
  ID_TOKEN_JWKS,
} from '../src/verify.js';

const PROJECT_ID = 'it-inventory-8e690';
const PROJECT_NUMBER = '315288299970';
const NOW = Date.parse('2026-09-21T12:00:00Z');
const SECONDS = Math.floor(NOW / 1000);

const ALGORITHM = { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' };

const toBase64Url = (bytes) =>
  Buffer.from(bytes).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

const encodeSegment = (value) => toBase64Url(new TextEncoder().encode(JSON.stringify(value)));

/** A fresh signing key, plus the JWK set that would verify it. */
async function makeKeys(kid = 'test-key') {
  const pair = await crypto.subtle.generateKey(
    { ...ALGORITHM, modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]) },
    true,
    ['sign', 'verify'],
  );

  const jwk = await crypto.subtle.exportKey('jwk', pair.publicKey);

  return { privateKey: pair.privateKey, jwks: { keys: [{ ...jwk, kid, alg: 'RS256', use: 'sig' }] }, kid };
}

/** Signs a JWT with [privateKey]. */
async function sign(privateKey, kid, payload, header = {}) {
  const signed = `${encodeSegment({ alg: 'RS256', kid, ...header })}.${encodeSegment(payload)}`;

  const signature = await crypto.subtle.sign(
    ALGORITHM,
    privateKey,
    new TextEncoder().encode(signed),
  );

  return `${signed}.${toBase64Url(new Uint8Array(signature))}`;
}

/** A well-formed Firebase ID token payload. */
const idPayload = (overrides = {}) => ({
  aud: PROJECT_ID,
  iss: `https://securetoken.google.com/${PROJECT_ID}`,
  sub: 'uid-123',
  email: 'admin@psba.test',
  email_verified: true,
  auth_time: SECONDS - 60,
  iat: SECONDS - 30,
  exp: SECONDS + 3600,
  ...overrides,
});

/** Serves [jwks] to anything that asks, and counts the asking. */
function stubFetch(jwks) {
  const calls = [];
  globalThis.fetch = async (url) => {
    calls.push(String(url));
    return { ok: true, json: async () => jwks };
  };
  return calls;
}

const realFetch = globalThis.fetch;

const verifyId = (token, now = NOW) =>
  verifyToken(token, {
    jwksUrl: ID_TOKEN_JWKS,
    checkClaims: (payload, ctx) => checkIdTokenClaims(payload, { ...ctx, projectId: PROJECT_ID }),
    now,
  });

test.afterEach(() => {
  globalThis.fetch = realFetch;
  resetKeyCache();
});

// ===========================================================================
// SHAPE
// ===========================================================================

test('anything that is not a three-part JWT is rejected outright', () => {
  for (const bad of ['', 'a.b', 'a.b.c.d', 'not a token', null, 42, {}]) {
    assert.equal(decodeJwt(bad), null, String(bad));
  }
});

test('a JWT whose segments are not JSON is rejected', () => {
  assert.equal(decodeJwt('aaaa.bbbb.cccc'), null);
});

// ===========================================================================
// A GENUINE TOKEN
// ===========================================================================

test('a properly signed ID token for this project is accepted', async () => {
  const { privateKey, jwks, kid } = await makeKeys();
  stubFetch(jwks);

  const result = await verifyId(await sign(privateKey, kid, idPayload()));

  assert.equal(result.ok, true);
  assert.equal(result.uid, 'uid-123');
  assert.equal(result.email, 'admin@psba.test');
  assert.equal(result.emailVerified, true);
});

test('an unverified email is reported, not silently accepted', async () => {
  const { privateKey, jwks, kid } = await makeKeys();
  stubFetch(jwks);

  const result = await verifyId(
    await sign(privateKey, kid, idPayload({ email_verified: false })),
  );

  assert.equal(result.ok, true);
  assert.equal(result.emailVerified, false);
});

test('email_verified must be the literal true', async () => {
  const { privateKey, jwks, kid } = await makeKeys();
  stubFetch(jwks);

  for (const value of ['true', 1, 'yes', undefined]) {
    const result = await verifyId(
      await sign(privateKey, kid, idPayload({ email_verified: value })),
    );
    assert.equal(result.emailVerified, false, String(value));
  }
});

test('the key set is fetched once and then reused', async () => {
  const { privateKey, jwks, kid } = await makeKeys();
  const calls = stubFetch(jwks);

  const token = await sign(privateKey, kid, idPayload());
  await verifyId(token);
  await verifyId(token);
  await verifyId(token);

  assert.equal(calls.length, 1);
  assert.equal(calls[0], ID_TOKEN_JWKS);
});

// ===========================================================================
// FORGERIES
// ===========================================================================

test('a token signed by the wrong key is refused', async () => {
  const mine = await makeKeys('test-key');
  const theirs = await makeKeys('test-key');

  // Google serves MY key; the attacker signed with THEIRS, under the same kid.
  stubFetch(mine.jwks);

  const result = await verifyId(await sign(theirs.privateKey, 'test-key', idPayload()));

  assert.equal(result.ok, false);
  assert.equal(result.reason, 'signature');
});

test('a tampered payload invalidates the signature', async () => {
  const { privateKey, jwks, kid } = await makeKeys();
  stubFetch(jwks);

  const token = await sign(privateKey, kid, idPayload());
  const [header, , signature] = token.split('.');

  // Same signature, a payload that now claims to be somebody else.
  const forged = `${header}.${encodeSegment(idPayload({ sub: 'uid-999' }))}.${signature}`;

  const result = await verifyId(forged);

  assert.equal(result.ok, false);
  assert.equal(result.reason, 'signature');
});

test('"alg: none" is refused before anything else happens', async () => {
  const { jwks } = await makeKeys();
  stubFetch(jwks);

  const unsigned = `${encodeSegment({ alg: 'none', kid: 'test-key' })}.${encodeSegment(
    idPayload(),
  )}.`;

  const result = await verifyId(unsigned);

  assert.equal(result.ok, false);
  assert.equal(result.reason, 'algorithm');
});

test('a token signed under an unknown key id is refused', async () => {
  const { privateKey, jwks } = await makeKeys('the-real-key');
  stubFetch(jwks);

  const result = await verifyId(await sign(privateKey, 'some-other-key', idPayload()));

  assert.equal(result.ok, false);
  assert.equal(result.reason, 'unknown_key');
});

test('an unreachable key set refuses rather than waving the caller through', async () => {
  globalThis.fetch = async () => ({ ok: false, status: 503, json: async () => ({}) });

  const { privateKey, kid } = await makeKeys();
  const result = await verifyId(await sign(privateKey, kid, idPayload()));

  assert.equal(result.ok, false);
  assert.equal(result.reason, 'keys_unavailable');
});

// ===========================================================================
// THE KEY CACHE - it must not turn an upstream blip into an outage
// ===========================================================================

test('a 200 carrying no usable keys is refused and NOT cached', async () => {
  const { privateKey, jwks, kid } = await makeKeys();
  const token = await sign(privateKey, kid, idPayload());

  // Google answers 200 with an error envelope instead of the key set: an
  // edge blip, a filtering proxy, a JSON error page.
  const bodies = [{}, { keys: [] }, { keys: null }, { error: { code: 503 } }, null];

  for (const body of bodies) {
    resetKeyCache();
    let served = 0;
    globalThis.fetch = async () => {
      served++;
      return { ok: true, json: async () => body };
    };

    const bad = await verifyId(token);
    assert.equal(bad.ok, false, JSON.stringify(body));
    assert.equal(bad.reason, 'keys_unavailable', JSON.stringify(body));

    // Google recovers a second later. The very next call must succeed, not
    // sit behind an hour of cached emptiness.
    globalThis.fetch = async () => ({ ok: true, json: async () => jwks });

    const good = await verifyId(token);
    assert.equal(good.ok, true, `did not recover after ${JSON.stringify(body)}`);
    assert.equal(served, 1, 'the empty set should not have been reused');
  }
});

test('a rotated signing key is picked up without waiting for the cache', async () => {
  const oldKeys = await makeKeys('key-of-january');
  const newKeys = await makeKeys('key-of-february');

  let served = oldKeys.jwks;
  let fetches = 0;
  globalThis.fetch = async () => {
    fetches++;
    return { ok: true, json: async () => served };
  };

  // Warm the cache with the old set.
  const before = await verifyId(await sign(oldKeys.privateKey, 'key-of-january', idPayload()));
  assert.equal(before.ok, true);
  assert.equal(fetches, 1);

  // Google rotates. A token under the new kid arrives while the cached set is
  // still well inside its hour.
  served = newKeys.jwks;

  const after = await verifyId(await sign(newKeys.privateKey, 'key-of-february', idPayload()));

  assert.equal(after.ok, true, 'a rotation should not lock everybody out');
  assert.equal(fetches, 2, 'exactly one extra fetch, on the unknown key id');
});

test('an unknown key id cannot be used to hammer Google', async () => {
  const { jwks, privateKey } = await makeKeys('the-real-key');

  let fetches = 0;
  globalThis.fetch = async () => {
    fetches++;
    return { ok: true, json: async () => jwks };
  };

  // Warm the cache.
  await verifyId(await sign(privateKey, 'the-real-key', idPayload()));
  assert.equal(fetches, 1);

  // Twenty tokens, each naming a key id that does not exist.
  for (let i = 0; i < 20; i++) {
    const result = await verifyId(await sign(privateKey, `made-up-${i}`, idPayload()));
    assert.equal(result.reason, 'unknown_key');
  }

  assert.equal(fetches, 2, 'forced refetches must be rate limited to one');
});

// ===========================================================================
// CLAIMS - the checks that pin a token to THIS project
// ===========================================================================

const check = (overrides, now = NOW) =>
  checkIdTokenClaims(idPayload(overrides), { projectId: PROJECT_ID, now });

test('a token minted for another Firebase project is refused', () => {
  assert.equal(check({ aud: 'someone-elses-project' }).reason, 'audience');
  assert.equal(
    check({ iss: 'https://securetoken.google.com/someone-elses-project' }).reason,
    'issuer',
  );
});

test('an expired token is refused', () => {
  assert.equal(check({ exp: SECONDS - 3600 }).reason, 'expired');
});

test('a token issued in the future is refused', () => {
  assert.equal(check({ iat: SECONDS + 3600 }).reason, 'issued_in_future');
  assert.equal(check({ auth_time: SECONDS + 3600 }).reason, 'auth_time');
});

test('a token with no subject is refused', () => {
  assert.equal(check({ sub: '' }).reason, 'subject');
  assert.equal(check({ sub: undefined }).reason, 'subject');
});

test('a little clock skew is tolerated, a lot is not', () => {
  assert.equal(check({ exp: SECONDS - 30 }).ok, true);
  assert.equal(check({ exp: SECONDS - 120 }).ok, false);
});

test('claims that are not there at all are refused, never defaulted', () => {
  assert.equal(checkIdTokenClaims(null, { projectId: PROJECT_ID, now: NOW }).reason, 'malformed');
  assert.equal(
    checkIdTokenClaims('a string', { projectId: PROJECT_ID, now: NOW }).reason,
    'malformed',
  );
});

// ===========================================================================
// APP CHECK
// ===========================================================================

const appCheck = (overrides = {}) =>
  checkAppCheckClaims(
    {
      iss: `https://firebaseappcheck.googleapis.com/${PROJECT_NUMBER}`,
      aud: [`projects/${PROJECT_NUMBER}`, `projects/${PROJECT_ID}`],
      sub: '1:315288299970:android:abc',
      exp: SECONDS + 1800,
      ...overrides,
    },
    { projectNumber: PROJECT_NUMBER, now: NOW },
  );

test('an App Check token for this project is accepted', () => {
  const result = appCheck();

  assert.equal(result.ok, true);
  assert.equal(result.appId, '1:315288299970:android:abc');
});

test('an App Check token for another project is refused', () => {
  assert.equal(appCheck({ iss: 'https://firebaseappcheck.googleapis.com/999' }).reason, 'issuer');
  assert.equal(appCheck({ aud: ['projects/999'] }).reason, 'audience');
});

test('an expired App Check token is refused', () => {
  assert.equal(appCheck({ exp: SECONDS - 3600 }).reason, 'expired');
});

test('a single-string audience is still read correctly', () => {
  assert.equal(appCheck({ aud: `projects/${PROJECT_NUMBER}` }).ok, true);
  assert.equal(appCheck({ aud: 'projects/999' }).reason, 'audience');
});
