/**
 * PSBA IT Inventory - Firebase token verification, outside Firebase.
 *
 * This Worker is not a Cloud Function, so it has no Admin SDK and no
 * privileged access to the project. It earns its trust the documented way
 * instead: by verifying Firebase's own signed tokens against Google's public
 * keys.
 *
 * Two tokens arrive with every request and both are checked:
 *
 *   - the Firebase **ID token**, which says who the caller is. Verified the
 *     way "Verify ID tokens using a third-party JWT library" describes:
 *     RS256, a `kid` present in Google's key set, `aud` equal to the project
 *     id, `iss` equal to `https://securetoken.google.com/<project id>`, and
 *     `exp`/`iat`/`auth_time` in the right direction.
 *
 *   - the Firebase **App Check** token, which says the call came from a
 *     genuine installation of this app rather than a script holding a stolen
 *     ID token. Firebase documents this for "non-Google custom backend
 *     resources, like your own self-hosted backend": RS256 against the JWKS
 *     at firebaseappcheck.googleapis.com, `iss`
 *     `https://firebaseappcheck.googleapis.com/<project number>` and an `aud`
 *     containing `projects/<project number>`.
 *
 * Nothing here trusts anything the client says about itself. A forged or
 * expired token fails the signature check, and every failure is a refusal.
 *
 * Only `fetch` (for the public key sets) touches the network; the rest is
 * pure and unit tested.
 */

/** Google's signing keys for Firebase ID tokens, as a JWK set. */
export const ID_TOKEN_JWKS =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';

/** Firebase's signing keys for App Check tokens. */
export const APP_CHECK_JWKS = 'https://firebaseappcheck.googleapis.com/v1/jwks';

/** A little slack for clock skew between Google's servers and this one. */
const CLOCK_SKEW_SECONDS = 60;

/** How long a fetched key set is reused before it is fetched again. */
const KEY_CACHE_MS = 60 * 60 * 1000;

/** The shortest gap between two forced refetches of the same key set. */
const KEY_REFRESH_MIN_MS = 5 * 60 * 1000;

/** base64url -> bytes. */
function fromBase64Url(value) {
  const padded = value.replace(/-/g, '+').replace(/_/g, '/');
  const binary = atob(padded + '='.repeat((4 - (padded.length % 4)) % 4));

  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);

  return bytes;
}

/** base64url -> parsed JSON, or null when it is not JSON at all. */
function decodeSegment(segment) {
  try {
    return JSON.parse(new TextDecoder().decode(fromBase64Url(segment)));
  } catch {
    return null;
  }
}

/**
 * Splits a JWT without verifying anything.
 *
 * Returns null for anything that is not three base64url segments carrying a
 * JSON header and payload.
 */
export function decodeJwt(token) {
  if (typeof token !== 'string') return null;

  const parts = token.split('.');
  if (parts.length !== 3) return null;

  const header = decodeSegment(parts[0]);
  const payload = decodeSegment(parts[1]);
  if (!header || !payload) return null;

  return { header, payload, signed: `${parts[0]}.${parts[1]}`, signature: parts[2] };
}

/**
 * Checks the claims of a Firebase ID token.
 *
 * Pure: the signature is checked separately, by [verifyToken]. Returns
 * `{ ok: true, uid, email, emailVerified }` or `{ ok: false, reason }`.
 */
export function checkIdTokenClaims(payload, { projectId, now }) {
  const seconds = Math.floor(now / 1000);

  if (!payload || typeof payload !== 'object') return { ok: false, reason: 'malformed' };
  if (payload.aud !== projectId) return { ok: false, reason: 'audience' };
  if (payload.iss !== `https://securetoken.google.com/${projectId}`) {
    return { ok: false, reason: 'issuer' };
  }

  if (typeof payload.sub !== 'string' || payload.sub === '') {
    return { ok: false, reason: 'subject' };
  }

  if (typeof payload.exp !== 'number' || payload.exp <= seconds - CLOCK_SKEW_SECONDS) {
    return { ok: false, reason: 'expired' };
  }
  if (typeof payload.iat !== 'number' || payload.iat > seconds + CLOCK_SKEW_SECONDS) {
    return { ok: false, reason: 'issued_in_future' };
  }
  if (typeof payload.auth_time === 'number' &&
      payload.auth_time > seconds + CLOCK_SKEW_SECONDS) {
    return { ok: false, reason: 'auth_time' };
  }

  return {
    ok: true,
    uid: payload.sub,
    email: typeof payload.email === 'string' ? payload.email : '',
    // The same bar firestore.rules sets for reading any inventory at all.
    emailVerified: payload.email_verified === true,
  };
}

/**
 * Checks the claims of a Firebase App Check token.
 *
 * `aud` is a list, because one token can be scoped to several projects.
 */
export function checkAppCheckClaims(payload, { projectNumber, now }) {
  const seconds = Math.floor(now / 1000);

  if (!payload || typeof payload !== 'object') return { ok: false, reason: 'malformed' };

  if (payload.iss !== `https://firebaseappcheck.googleapis.com/${projectNumber}`) {
    return { ok: false, reason: 'issuer' };
  }

  const audience = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (!audience.includes(`projects/${projectNumber}`)) {
    return { ok: false, reason: 'audience' };
  }

  if (typeof payload.exp !== 'number' || payload.exp <= seconds - CLOCK_SKEW_SECONDS) {
    return { ok: false, reason: 'expired' };
  }

  return { ok: true, appId: typeof payload.sub === 'string' ? payload.sub : '' };
}

/**
 * Fetches and caches a JWK set.
 *
 * The cache lives on the isolate, so a cold start pays one extra request and
 * everything after it is free. Waiting on that fetch does not count against
 * the Worker's CPU budget.
 */
const keyCache = new Map();

async function loadKeys(url, now, { force = false } = {}) {
  const cached = keyCache.get(url);

  if (!force && cached && cached.until > now) return cached.keys;

  if (force && cached) {
    // Forced refetches are rate limited on their own clock, not the cache's,
    // so the FIRST unknown key id always gets a fresh look - that is the one
    // that means "Google has rotated" - while a stream of made-up ids after
    // it cannot be used to hammer Google's endpoint through us.
    if (cached.forcedAt !== undefined && now - cached.forcedAt < KEY_REFRESH_MIN_MS) {
      return cached.keys;
    }
    cached.forcedAt = now;
  }

  const response = await fetch(url);
  if (!response.ok) throw new Error(`Key set unavailable (${response.status})`);

  const body = await response.json();
  const keys = new Map();

  for (const key of (body && body.keys) || []) {
    if (key && typeof key.kid === 'string') keys.set(key.kid, key);
  }

  // A key set with nothing usable in it is not an answer, it is a failure
  // wearing a 200 - an error envelope, a filtering proxy, an edge blip. It
  // must not be cached: doing so would turn one bad second upstream into an
  // hour of refusing every signed-in user, which is a self-inflicted outage
  // rather than the caution it looks like.
  if (keys.size === 0) throw new Error('Key set contained no usable keys');

  keyCache.set(url, {
    keys,
    until: now + KEY_CACHE_MS,
    // Carried across the refill so the rate limit is not reset by the very
    // refetch it just allowed.
    forcedAt: force ? now : cached && cached.forcedAt,
  });

  return keys;
}

/** Only for tests: forget everything that has been fetched. */
export function resetKeyCache() {
  keyCache.clear();
}

/**
 * Verifies a token's signature against a key set, then its claims.
 *
 * [checkClaims] is one of the two pure checkers above.
 */
export async function verifyToken(token, { jwksUrl, checkClaims, now }) {
  const decoded = decodeJwt(token);
  if (!decoded) return { ok: false, reason: 'malformed' };

  // RS256 and nothing else. Accepting the token's own idea of its algorithm
  // is how "alg: none" attacks work.
  if (decoded.header.alg !== 'RS256') return { ok: false, reason: 'algorithm' };
  if (typeof decoded.header.kid !== 'string') return { ok: false, reason: 'key_id' };

  let keys;
  try {
    keys = await loadKeys(jwksUrl, now);
  } catch {
    return { ok: false, reason: 'keys_unavailable' };
  }

  let jwk = keys.get(decoded.header.kid);

  if (!jwk) {
    // Google rotates these signing keys. An unknown id usually means nothing
    // worse than a cached set that has gone stale, so it is fetched once more
    // before a genuine token is turned away - otherwise a rotation would lock
    // every user out until the cache expired on its own.
    try {
      const fresh = await loadKeys(jwksUrl, now, { force: true });
      jwk = fresh.get(decoded.header.kid);
    } catch {
      // Keep the refusal below; the key set is unreachable either way.
    }
  }

  if (!jwk) return { ok: false, reason: 'unknown_key' };

  const algorithm = { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' };

  let valid = false;
  try {
    const key = await crypto.subtle.importKey('jwk', { ...jwk, alg: 'RS256' }, algorithm, false, [
      'verify',
    ]);

    valid = await crypto.subtle.verify(
      algorithm,
      key,
      fromBase64Url(decoded.signature),
      new TextEncoder().encode(decoded.signed),
    );
  } catch {
    return { ok: false, reason: 'signature' };
  }

  if (!valid) return { ok: false, reason: 'signature' };

  return checkClaims(decoded.payload, { now });
}
