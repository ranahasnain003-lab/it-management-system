/**
 * PSBA IT Inventory - the per-account request counter.
 *
 * The Cloud Function kept this in Firestore, inside a transaction, so two
 * questions asked at once could not both slip past the daily cap. There is no
 * Admin SDK here, so the counter lives in a Durable Object instead - one
 * object per account, addressed by uid.
 *
 * That gives the same guarantee for the same reason: a Durable Object handles
 * its requests one at a time, so the read-decide-write below is atomic
 * without a transaction. It also keeps the decision itself in usage_policy.js,
 * unchanged and still pure, so the cap behaves exactly as it always has.
 *
 * SQLite-backed Durable Objects are included in the Workers Free plan.
 */
import { DAILY_LIMIT, MIN_INTERVAL_MS, evaluateUsage } from './usage_policy.js';

export class UsageCounter {
  constructor(state) {
    this.state = state;
  }

  /**
   * Counts one request against this account's cap.
   *
   * The body carries the current time so the decision stays testable and so
   * the whole policy is driven from one clock.
   */
  async fetch(request) {
    let now = Date.now();

    try {
      const body = await request.json();
      if (body && typeof body.now === 'number') now = body.now;
    } catch {
      // No body, or not JSON. The Worker's own clock stands.
    }

    const record = (await this.state.storage.get('usage')) || null;

    const decision = evaluateUsage({
      record,
      now,
      dailyLimit: DAILY_LIMIT,
      minIntervalMs: MIN_INTERVAL_MS,
    });

    // Only a request that is actually going ahead is counted, which is what
    // keeps a throttled caller from pushing their own allowance further away.
    if (decision.allowed) {
      await this.state.storage.put('usage', decision.record);
    }

    return new Response(JSON.stringify(decision), {
      headers: { 'content-type': 'application/json' },
    });
  }
}
