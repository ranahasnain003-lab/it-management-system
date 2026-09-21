/**
 * PSBA IT Inventory - AI Assistant usage policy.
 *
 * Pure decision logic, deliberately free of Firebase and network calls so it
 * can be unit tested directly with `node --test`. index.js supplies the stored
 * counter and the current time; this file decides whether the call may spend
 * spend a request on the model, and what the counter should become.
 */
/** Requests one signed-in account may make in one calendar day. */
const DAILY_LIMIT = 60;

/** Shortest gap between two requests from the same account. */
const MIN_INTERVAL_MS = 3000;

/** The day resets on the operator's local calendar, not UTC. */
const TIME_ZONE = 'Asia/Karachi';

const DAY_MS = 86400000;

/** Never ask a caller to wait longer than this, whatever a bad clock says. */
const MAX_RETRY_SECONDS = 24 * 60 * 60;

/**
 * The calendar day an instant falls in, as `YYYY-MM-DD`, in [timeZone].
 */
function dayKey(instantMs, timeZone = TIME_ZONE) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date(instantMs));
}

/**
 * Offset between wall-clock time in [timeZone] and UTC at that instant, in ms.
 */
function zoneOffsetMs(instantMs, timeZone) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hour12: false,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).formatToParts(new Date(instantMs));

  const field = {};
  for (const part of parts) field[part.type] = part.value;

  const asUtc = Date.UTC(
    Number(field.year),
    Number(field.month) - 1,
    Number(field.day),
    Number(field.hour) % 24,
    Number(field.minute),
    Number(field.second),
  );

  // Both sides are truncated to whole seconds so the sub-second part of
  // instantMs does not leak into the offset.
  return asUtc - Math.floor(instantMs / 1000) * 1000;
}

/** Milliseconds from [instantMs] until midnight in [timeZone]. */
function msUntilNextDay(instantMs, timeZone = TIME_ZONE) {
  const local = instantMs + zoneOffsetMs(instantMs, timeZone);
  const sinceMidnight = ((local % DAY_MS) + DAY_MS) % DAY_MS;
  return DAY_MS - sinceMidnight;
}

function toCount(value) {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0;
}

function toMillis(value) {
  if (value == null) return 0;
  // A Firestore Timestamp, a Date, or a plain number of milliseconds.
  if (typeof value === 'object' && typeof value.toMillis === 'function') {
    return toCount(value.toMillis());
  }
  if (value instanceof Date) return toCount(value.getTime());
  return toCount(value);
}

function clampSeconds(ms) {
  const seconds = Math.ceil(ms / 1000);
  if (!Number.isFinite(seconds) || seconds < 1) return 1;
  return Math.min(seconds, MAX_RETRY_SECONDS);
}

/**
 * Decides whether one account may make another assistant request.
 *
 * [record] is the stored `ai_usage/{uid}` document (or null the first time).
 * Returns `{ allowed, reason, retryAfterSeconds, used, remaining, limit, day }`
 * and, when allowed, `record` — the counter state the caller must store.
 *
 * The counter is never trusted to be well formed: a missing, corrupt or
 * hand-edited document is read as "no usage yet" rather than as unlimited
 * usage, so the worst a bad document can do is reset the day.
 */
function evaluateUsage(options = {}) {
  const now = toCount(options.now);
  const record = options.record && typeof options.record === 'object'
      ? options.record
      : null;
  const timeZone = options.timeZone || TIME_ZONE;
  const dailyLimit = Number.isFinite(options.dailyLimit) && options.dailyLimit > 0
      ? Math.floor(options.dailyLimit)
      : DAILY_LIMIT;
  const minIntervalMs = Number.isFinite(options.minIntervalMs) && options.minIntervalMs >= 0
      ? options.minIntervalMs
      : MIN_INTERVAL_MS;

  const today = dayKey(now, timeZone);
  const sameDay = record != null && record.day === today;
  const used = sameDay ? toCount(record.count) : 0;

  // The burst gap is measured across the day boundary too, so a user cannot
  // fire two calls back to back by waiting for midnight.
  const lastAt = record != null ? toMillis(record.lastRequestAt) : 0;
  // A stored time in the future means a skewed clock, not a time machine.
  const sinceLast = lastAt > 0 ? Math.max(0, now - lastAt) : Number.MAX_SAFE_INTEGER;

  const base = { used, remaining: Math.max(0, dailyLimit - used), limit: dailyLimit, day: today };

  if (sinceLast < minIntervalMs) {
    return {
      ...base,
      allowed: false,
      reason: 'too_fast',
      retryAfterSeconds: clampSeconds(minIntervalMs - sinceLast),
    };
  }

  if (used >= dailyLimit) {
    return {
      ...base,
      allowed: false,
      reason: 'daily_cap',
      retryAfterSeconds: clampSeconds(msUntilNextDay(now, timeZone)),
    };
  }

  const count = used + 1;

  return {
    allowed: true,
    reason: 'ok',
    retryAfterSeconds: 0,
    used: count,
    remaining: Math.max(0, dailyLimit - count),
    limit: dailyLimit,
    day: today,
    record: { day: today, count, lastRequestAt: now },
  };
}

/**
 * Whether App Check must be enforced, read from the deploy environment.
 *
 * The default is "enforce". Enforcement is only switched off by setting
 * `AI_REQUIRE_APP_CHECK=false`, which is needed while the Android build is
 * distributed as a side-loaded APK, because the Play Integrity provider only
 * issues tokens for builds installed from Google Play.
 */
function appCheckRequired(env = {}) {
  const raw = env.AI_REQUIRE_APP_CHECK;
  if (raw === undefined || raw === null || String(raw).trim() === '') return true;

  const value = String(raw).trim().toLowerCase();
  return !(value === 'false' || value === '0' || value === 'no' || value === 'off');
}

/**
 * Decides whether a call passes App Check. [hasValidToken] must be true only
 * when the Functions runtime itself verified the token.
 */
function evaluateAppCheck(options = {}) {
  if (!options.required) return { allowed: true, reason: 'not_enforced' };
  if (options.hasValidToken === true) return { allowed: true, reason: 'ok' };
  return { allowed: false, reason: 'missing_app_check' };
}

export {
  DAILY_LIMIT,
  MIN_INTERVAL_MS,
  TIME_ZONE,
  dayKey,
  msUntilNextDay,
  evaluateUsage,
  appCheckRequired,
  evaluateAppCheck,
};