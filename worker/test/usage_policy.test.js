/**
 * Tests for the AI Assistant usage policy: the per-account daily cap, the
 * burst interval and App Check enforcement.
 *
 * Run with: npm test --prefix worker   (or: node --test worker/test/)
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  DAILY_LIMIT,
  MIN_INTERVAL_MS,
  dayKey,
  msUntilNextDay,
  evaluateUsage,
  appCheckRequired,
  evaluateAppCheck,
} from '../src/usage_policy.js';

// 2026-09-17 11:00 in Asia/Karachi (UTC+5).
const NOON = Date.parse('2026-09-17T06:00:00Z');
const LONG_AGO = NOON - 60 * 60 * 1000;

const at = (record, now = NOON) => evaluateUsage({ record, now });

// ===========================================================================
// DAY KEYS
// ===========================================================================

test('the day is the operator local day, not the UTC day', () => {
  assert.equal(dayKey(NOON), '2026-09-17');

  // 20:00 UTC is already the next day in Karachi.
  assert.equal(dayKey(Date.parse('2026-09-17T20:00:00Z')), '2026-09-18');
  // One minute before local midnight is still the same day.
  assert.equal(dayKey(Date.parse('2026-09-17T18:59:00Z')), '2026-09-17');
});

test('the wait after a daily cap ends at local midnight', () => {
  assert.equal(msUntilNextDay(NOON), 13 * 60 * 60 * 1000);
  assert.equal(msUntilNextDay(Date.parse('2026-09-17T18:59:00Z')), 60 * 1000);
});

// ===========================================================================
// DAILY CAP
// ===========================================================================

test('the first request of an account is allowed and starts the counter', () => {
  const decision = at(null);

  assert.equal(decision.allowed, true);
  assert.equal(decision.used, 1);
  assert.equal(decision.remaining, DAILY_LIMIT - 1);
  assert.deepEqual(decision.record, {
    day: '2026-09-17',
    count: 1,
    lastRequestAt: NOON,
  });
});

test('requests below the cap are allowed and increment the stored count', () => {
  const decision = at({ day: '2026-09-17', count: 5, lastRequestAt: LONG_AGO });

  assert.equal(decision.allowed, true);
  assert.equal(decision.record.count, 6);
  assert.equal(decision.remaining, DAILY_LIMIT - 6);
});

test('the request that reaches the cap is still allowed', () => {
  const decision = at({
    day: '2026-09-17',
    count: DAILY_LIMIT - 1,
    lastRequestAt: LONG_AGO,
  });

  assert.equal(decision.allowed, true);
  assert.equal(decision.remaining, 0);
});

test('the request after the cap is refused until local midnight', () => {
  const decision = at({
    day: '2026-09-17',
    count: DAILY_LIMIT,
    lastRequestAt: LONG_AGO,
  });

  assert.equal(decision.allowed, false);
  assert.equal(decision.reason, 'daily_cap');
  assert.equal(decision.retryAfterSeconds, 13 * 60 * 60);
  assert.equal(decision.record, undefined);
});

test('a count already above the cap stays refused', () => {
  const decision = at({
    day: '2026-09-17',
    count: DAILY_LIMIT + 500,
    lastRequestAt: LONG_AGO,
  });

  assert.equal(decision.allowed, false);
  assert.equal(decision.reason, 'daily_cap');
  assert.equal(decision.remaining, 0);
});

test('the counter resets on the next day', () => {
  const decision = at({
    day: '2026-09-16',
    count: DAILY_LIMIT,
    lastRequestAt: LONG_AGO,
  });

  assert.equal(decision.allowed, true);
  assert.equal(decision.record.day, '2026-09-17');
  assert.equal(decision.record.count, 1);
});

// ===========================================================================
// BURST INTERVAL
// ===========================================================================

test('two requests in the same second are refused', () => {
  const decision = at({ day: '2026-09-17', count: 1, lastRequestAt: NOON - 500 });

  assert.equal(decision.allowed, false);
  assert.equal(decision.reason, 'too_fast');
  assert.ok(decision.retryAfterSeconds >= 1);
  assert.ok(decision.retryAfterSeconds <= Math.ceil(MIN_INTERVAL_MS / 1000));
});

test('a request after the burst interval is allowed', () => {
  const decision = at({
    day: '2026-09-17',
    count: 1,
    lastRequestAt: NOON - MIN_INTERVAL_MS,
  });

  assert.equal(decision.allowed, true);
});

test('the burst interval still applies across a day change', () => {
  const justAfterMidnight = Date.parse('2026-09-17T19:00:01Z');
  const decision = evaluateUsage({
    record: { day: '2026-09-17', count: 9, lastRequestAt: justAfterMidnight - 200 },
    now: justAfterMidnight,
  });

  assert.equal(decision.allowed, false);
  assert.equal(decision.reason, 'too_fast');
});

// ===========================================================================
// UNTRUSTED COUNTER DOCUMENTS
// ===========================================================================

test('a corrupt counter is read as no usage, never as unlimited usage', () => {
  for (const record of [
    {},
    { day: 42, count: 'lots' },
    { day: '2026-09-17', count: 'lots', lastRequestAt: 'yesterday' },
    { day: '2026-09-17', count: -9999, lastRequestAt: null },
    { day: null, count: null, lastRequestAt: undefined },
  ]) {
    const decision = at(record);

    assert.equal(decision.allowed, true, JSON.stringify(record));
    assert.equal(decision.record.count, 1, JSON.stringify(record));
    assert.equal(decision.record.day, '2026-09-17');
  }
});

test('a Firestore Timestamp is accepted as the last request time', () => {
  const decision = at({
    day: '2026-09-17',
    count: 2,
    lastRequestAt: { toMillis: () => NOON - 500 },
  });

  assert.equal(decision.allowed, false);
  assert.equal(decision.reason, 'too_fast');
});

test('a last request time in the future throttles but never locks an account out', () => {
  const decision = at({
    day: '2026-09-17',
    count: 1,
    lastRequestAt: NOON + 10 * 365 * 24 * 60 * 60 * 1000,
  });

  assert.equal(decision.allowed, false);
  assert.equal(decision.reason, 'too_fast');
  assert.ok(decision.retryAfterSeconds <= Math.ceil(MIN_INTERVAL_MS / 1000));
});

// ===========================================================================
// APP CHECK
// ===========================================================================

test('App Check is enforced unless it is explicitly switched off', () => {
  assert.equal(appCheckRequired({}), true);
  assert.equal(appCheckRequired({ AI_REQUIRE_APP_CHECK: '' }), true);
  assert.equal(appCheckRequired({ AI_REQUIRE_APP_CHECK: 'true' }), true);
  assert.equal(appCheckRequired({ AI_REQUIRE_APP_CHECK: 'yes' }), true);
  assert.equal(appCheckRequired({ AI_REQUIRE_APP_CHECK: 'anything else' }), true);

  assert.equal(appCheckRequired({ AI_REQUIRE_APP_CHECK: 'false' }), false);
  assert.equal(appCheckRequired({ AI_REQUIRE_APP_CHECK: 'FALSE' }), false);
  assert.equal(appCheckRequired({ AI_REQUIRE_APP_CHECK: '0' }), false);
  assert.equal(appCheckRequired({ AI_REQUIRE_APP_CHECK: 'off' }), false);
});

test('a call without a verified App Check token is refused while enforced', () => {
  assert.equal(
    evaluateAppCheck({ required: true, hasValidToken: false }).allowed,
    false,
  );
  assert.equal(
    evaluateAppCheck({ required: true }).reason,
    'missing_app_check',
  );
  assert.equal(
    evaluateAppCheck({ required: true, hasValidToken: true }).allowed,
    true,
  );
  assert.equal(
    evaluateAppCheck({ required: false, hasValidToken: false }).allowed,
    true,
  );
});

test('only a real verification counts as a token', () => {
  // request.app is an object when the runtime verified the token; anything
  // truthy-looking that is not an explicit true must not pass.
  assert.equal(
    evaluateAppCheck({ required: true, hasValidToken: 'yes' }).allowed,
    false,
  );
});
