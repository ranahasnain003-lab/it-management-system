/**
 * PSBA IT Inventory - Google Gemini adapter.
 *
 * One provider, one file. The assistant asks Gemini for the SAME structured
 * reply every other part of this backend expects (see REPLY_SCHEMA in
 * assistant_prompt.js), through Gemini's function-calling channel, so the
 * answer arrives as JSON rather than prose that has to be scraped.
 *
 * Gemini was chosen because its API has a genuine free tier: it needs an API
 * key from Google AI Studio and no billing account at all. The key is passed
 * in as an argument and never read from this module - it lives in Cloudflare's
 * secret store, set with `wrangler secret put`, and reaches the Worker only as
 * a binding. It is never in the app, the APK, the web bundle or the
 * repository.
 *
 * Everything except the single `fetch` is pure, so `selectModel`,
 * `buildGeminiBody` and `readGeminiReply` are unit tested without a network.
 */
import { REPLY_SCHEMA } from './assistant_prompt.js';

/** The single function Gemini is told to call. */
const TOOL_NAME = 'reply';

const TOOL_DESCRIPTION =
  'Give your reply to the user, and - only if the user was instructing rather ' +
  'than asking - the change you believe they want. The app re-checks and ' +
  'confirms every change; calling this never carries anything out.';

/**
 * The model.
 *
 * Chosen by measurement on 2026-09-27, and the measurement that decides it is
 * the free tier's DAILY request allowance, which is counted per model
 * (`GenerateRequestsPerDayPerProjectPerModel-FreeTier`):
 *
 *   gemini-3.6-flash       20 requests/day   (measured, then exhausted)
 *   gemini-3.8-flash       20 requests/day   (measured, then exhausted)
 *   gemini-3.5-flash-lite  comfortably more  (26+ in one run, no refusal)
 *
 * Twenty questions a day is not an assistant, and it fails with HTTP 429
 * rather than a wrong answer, so it reads as an outage. The Lite model is the
 * only free option with usable headroom.
 *
 * The cost is real and worth stating: asked an unrecognised multi-record
 * question - the printers at Head Office, where 8 are working and 8 are
 * damaged - Lite reported only the damaged ones, while 3.8-flash reported
 * both. That gap closes when the app supplies its own computed answer, which
 * it does for every question its on-device engine understands: handed the
 * grounded figures, Lite answered the same question correctly.
 *
 * So: Lite for volume, with the app's own arithmetic as the safety net. To
 * trade volume back for accuracy on unrecognised questions, set
 * AI_MODEL = "gemini-3.8-flash" and accept 20 requests a day.
 */
const DEFAULT_MODEL = 'gemini-3.5-flash-lite';

const GEMINI_ENDPOINT = 'https://generativelanguage.googleapis.com/v1beta/models';

/**
 * Transient refusals: the request was fine, the service was momentarily not.
 *
 * The free tier really does return 503 UNAVAILABLE ("this model is currently
 * experiencing high demand") a good share of the time - often enough that a
 * single attempt fails more often than it succeeds. Retrying is what makes the
 * difference between an assistant that answers and one that looks broken.
 *
 * 400, 401, 403 and 404 are NOT here on purpose: a bad key, a wrong model or a
 * malformed body will fail identically however many times it is sent, and
 * retrying one only burns the caller's deadline.
 */
const RETRYABLE_STATUSES = new Set([429, 500, 502, 503, 504]);

/** Attempts in total, not retries after the first. */
const MAX_ATTEMPTS = 3;

/**
 * Base wait between attempts, multiplied by the attempt number.
 *
 * So 600ms then 1200ms: 1.8s of waiting at worst, which leaves the caller's
 * 20s abort room for the third attempt. Waiting costs no CPU time, so this
 * stays well inside the free plan's 10ms CPU limit.
 */
const RETRY_DELAY_MS = 600;

/**
 * Room for the answer.
 *
 * Generous on purpose. Current Flash models think before answering and those
 * thinking tokens are counted against this same limit, so a tight budget shows
 * up as a truncated reply - which is discarded whole, because the part that
 * went missing may be the part that carried a figure. On the free tier the
 * headroom costs nothing: the limits are requests per minute and per day, not
 * tokens.
 */
const MAX_OUTPUT_TOKENS = 8192;

/** Low, so the wording stays close to the facts. */
const TEMPERATURE = 0.2;

/**
 * Which model this deployment talks to.
 *
 * Read from the environment so a deployment can be moved to another free Flash
 * model without a code change.
 */
function selectModel(env = {}) {
  const configured = String(env.AI_MODEL || '').trim();

  return { model: configured || DEFAULT_MODEL };
}

/**
 * The request body for `models/{model}:generateContent`.
 *
 * Gemini names the two conversation roles `user` and `model`, so the
 * provider-neutral turns built by assistant_prompt.js are mapped here rather
 * than there. The system prompt is a top-level `systemInstruction`, which is
 * what keeps it out of the conversation the user can write into.
 */
function buildGeminiBody({ system, messages }) {
  return {
    systemInstruction: { parts: [{ text: system }] },
    contents: messages.map((turn) => ({
      role: turn.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: turn.content }],
    })),
    tools: [
      {
        functionDeclarations: [
          {
            name: TOOL_NAME,
            description: TOOL_DESCRIPTION,
            parameters: REPLY_SCHEMA,
          },
        ],
      },
    ],
    // The reply must come back as this function's arguments, never as prose.
    toolConfig: {
      functionCallingConfig: {
        mode: 'ANY',
        allowedFunctionNames: [TOOL_NAME],
      },
    },
    generationConfig: {
      temperature: TEMPERATURE,
      maxOutputTokens: MAX_OUTPUT_TOKENS,
    },
  };
}

/**
 * Pulls the structured reply out of a Gemini response.
 *
 * Returns `{ raw, truncated, text }`. `raw` is the object the model produced,
 * or null when it did not call the function; `truncated` marks a reply cut off
 * at the token limit, which the caller discards rather than show half of.
 */
function readGeminiReply(body) {
  if (!body || typeof body !== 'object') return { raw: null, truncated: false };

  const candidate = Array.isArray(body.candidates) ? body.candidates[0] : null;

  // The whole prompt can be refused before a candidate is ever produced, for
  // instance by a safety filter. There is nothing to read in that case.
  if (!candidate) return { raw: null, truncated: false };

  const truncated = candidate.finishReason === 'MAX_TOKENS';

  const parts =
    candidate.content && Array.isArray(candidate.content.parts)
      ? candidate.content.parts
      : [];

  for (const part of parts) {
    const call = part && part.functionCall;
    if (call && call.name === TOOL_NAME) {
      return { raw: call.args || null, truncated };
    }
  }

  // No function call: hand back any text for one parse attempt before the
  // caller gives up and keeps the locally computed answer.
  const text = parts
    .filter((p) => p && typeof p.text === 'string')
    .map((p) => p.text)
    .join('\n')
    .trim();

  return { raw: null, truncated, text };
}

/**
 * Calls Gemini.
 *
 * Throws an Error carrying `status` when Gemini refuses, so the caller can log
 * the status without logging the body - an error body can echo request content
 * straight back into the logs.
 */
async function callModel({ model, apiKey, system, messages, signal }) {
  const url = `${GEMINI_ENDPOINT}/${encodeURIComponent(model)}:generateContent`;
  const body = JSON.stringify(buildGeminiBody({ system, messages }));

  let lastStatus = 0;
  let lastDetail = '';

  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    const response = await fetch(url, {
      method: 'POST',
      signal,
      headers: {
        'content-type': 'application/json',
        // Header, never a query parameter: a key in a URL ends up in logs.
        'x-goog-api-key': apiKey,
      },
      body,
    });

    if (response.ok) return readGeminiReply(await response.json());

    lastStatus = response.status;

    // The reason, for the log. Read before deciding, because a body can only
    // be consumed once and a retry uses a fresh response anyway.
    lastDetail = await response.text().then(
      (text) => text.slice(0, 200),
      () => '',
    );

    const worthRetrying =
      RETRYABLE_STATUSES.has(response.status) && attempt < MAX_ATTEMPTS;

    if (!worthRetrying) break;

    // Flat, short waits. The caller aborts the whole thing at 15s, so the
    // budget has to leave room for the attempt that follows the wait.
    await new Promise((resolve) => setTimeout(resolve, RETRY_DELAY_MS * attempt));
  }

  const error = new Error(`Gemini refused the call (${lastStatus})`);
  error.status = lastStatus;
  error.detail = lastDetail;
  throw error;
}

export {
  TOOL_NAME,
  TOOL_DESCRIPTION,
  DEFAULT_MODEL,
  GEMINI_ENDPOINT,
  RETRYABLE_STATUSES,
  MAX_ATTEMPTS,
  RETRY_DELAY_MS,
  MAX_OUTPUT_TOKENS,
  TEMPERATURE,
  selectModel,
  buildGeminiBody,
  readGeminiReply,
  callModel,
};