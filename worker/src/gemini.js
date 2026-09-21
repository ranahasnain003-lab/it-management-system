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
 * `gemini-3.6-flash` is a current, stable Flash model listed as free of charge
 * on the Gemini API pricing page, and described for "general agentic and
 * everyday tasks" - which is what answering questions about a page of
 * inventory facts is. Overridable at deploy time with AI_MODEL, so moving to
 * another free Flash model never needs a code change.
 */
const DEFAULT_MODEL = 'gemini-3.6-flash';

const GEMINI_ENDPOINT = 'https://generativelanguage.googleapis.com/v1beta/models';

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

  const response = await fetch(url, {
    method: 'POST',
    signal,
    headers: {
      'content-type': 'application/json',
      // Header, never a query parameter: a key in a URL ends up in logs.
      'x-goog-api-key': apiKey,
    },
    body: JSON.stringify(buildGeminiBody({ system, messages })),
  });

  if (!response.ok) {
    const error = new Error(`Gemini refused the call (${response.status})`);
    error.status = response.status;
    throw error;
  }

  return readGeminiReply(await response.json());
}

export {
  TOOL_NAME,
  TOOL_DESCRIPTION,
  DEFAULT_MODEL,
  GEMINI_ENDPOINT,
  MAX_OUTPUT_TOKENS,
  TEMPERATURE,
  selectModel,
  buildGeminiBody,
  readGeminiReply,
  callModel,
};