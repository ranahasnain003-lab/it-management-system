/**
 * Tests for the Gemini adapter: which model a deployment talks to, what is
 * sent, and what is believed of what comes back.
 *
 * No network: only the pure request builder and response reader are exercised,
 * which is everything except the single fetch call.
 *
 * Run with: npm test --prefix worker   (or: node --test worker/test/)
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  TOOL_NAME,
  DEFAULT_MODEL,
  GEMINI_ENDPOINT,
  MAX_OUTPUT_TOKENS,
  selectModel,
  buildGeminiBody,
  readGeminiReply,
  callModel,
  RETRYABLE_STATUSES,
  MAX_ATTEMPTS,
  RETRY_DELAY_MS,
} from '../src/gemini.js';

import {
  REPLY_SCHEMA,
  buildMessages,
  normaliseReply,
} from '../src/assistant_prompt.js';

const PROMPT = {
  system: 'system rules',
  messages: [
    { role: 'user', content: 'how many laptops?' },
    { role: 'assistant', content: 'There are 12.' },
    { role: 'user', content: 'and the printers?' },
  ],
};

// ===========================================================================
// CHOOSING A MODEL
// ===========================================================================

test('the default is a stable free-tier Flash model', () => {
  // A Lite model, because the free tier's daily allowance is counted PER
  // MODEL and both gemini-3.6-flash and gemini-3.8-flash were measured at 20
  // requests a day - which is not an assistant. Lite served 26+ in one run
  // without a refusal. See the note on DEFAULT_MODEL for the accuracy
  // trade-off and how to reverse it.
  assert.deepEqual(selectModel({}), { model: 'gemini-3.5-flash-lite' });
  assert.equal(DEFAULT_MODEL, 'gemini-3.5-flash-lite');
});

test('the model can be moved without a code change', () => {
  assert.equal(selectModel({ AI_MODEL: 'gemini-2.5-flash' }).model, 'gemini-2.5-flash');
  assert.equal(selectModel({ AI_MODEL: '  gemini-3.5-flash  ' }).model, 'gemini-3.5-flash');
});

test('an empty setting falls back to the default rather than failing', () => {
  assert.equal(selectModel({ AI_MODEL: '   ' }).model, DEFAULT_MODEL);
  assert.equal(selectModel().model, DEFAULT_MODEL);
});

test('the endpoint is the Gemini generateContent API', () => {
  assert.equal(
    GEMINI_ENDPOINT,
    'https://generativelanguage.googleapis.com/v1beta/models',
  );
});

// ===========================================================================
// WHAT IS SENT
// ===========================================================================

test('the system prompt is a systemInstruction, not a conversation turn', () => {
  // It has to sit outside `contents`, where the user cannot write into it.
  const body = buildGeminiBody(PROMPT);

  assert.deepEqual(body.systemInstruction, { parts: [{ text: 'system rules' }] });
  for (const turn of body.contents) {
    assert.notEqual(turn.parts[0].text, 'system rules');
  }
});

test('assistant turns are renamed to Gemini\'s "model" role', () => {
  const body = buildGeminiBody(PROMPT);

  assert.deepEqual(
    body.contents.map((c) => c.role),
    ['user', 'model', 'user'],
  );
  assert.equal(body.contents[1].parts[0].text, 'There are 12.');
});

test('the conversation opens on a user turn', () => {
  assert.equal(buildGeminiBody(PROMPT).contents[0].role, 'user');
});

test('the reply is demanded through the function channel only', () => {
  const body = buildGeminiBody(PROMPT);

  assert.equal(body.tools.length, 1);
  assert.equal(body.tools[0].functionDeclarations.length, 1);
  assert.equal(body.tools[0].functionDeclarations[0].name, TOOL_NAME);
  assert.deepEqual(body.tools[0].functionDeclarations[0].parameters, REPLY_SCHEMA);
  assert.deepEqual(body.toolConfig, {
    functionCallingConfig: { mode: 'ANY', allowedFunctionNames: [TOOL_NAME] },
  });
});

test('the schema uses only types Gemini accepts', () => {
  // Gemini's function-declaration schema is a narrow subset: lower-case type
  // names, and no union types.
  const allowed = new Set([
    'object', 'array', 'string', 'integer', 'number', 'boolean',
  ]);

  const walk = (node, path) => {
    if (!node || typeof node !== 'object') return;

    if ('type' in node) {
      assert.equal(
        typeof node.type,
        'string',
        `${path}.type must be a single string, not a union`,
      );
      assert.ok(allowed.has(node.type), `${path}.type is "${node.type}"`);
    }

    for (const [key, child] of Object.entries(node.properties || {})) {
      walk(child, `${path}.${key}`);
    }
    if (node.items) walk(node.items, `${path}[]`);
  };

  walk(REPLY_SCHEMA, 'reply');
});

test('the answer is required but the action is not', () => {
  assert.ok(REPLY_SCHEMA.required.includes('answer'));
  assert.equal(REPLY_SCHEMA.required.includes('action'), false);
});

test('there is room for a long answer plus any thinking before it', () => {
  // Flash models think before answering and those tokens come out of the same
  // budget; a truncated reply is discarded whole.
  assert.ok(MAX_OUTPUT_TOKENS >= 8192);
  assert.equal(buildGeminiBody(PROMPT).generationConfig.maxOutputTokens, MAX_OUTPUT_TOKENS);
});

test('the temperature is low, so wording stays close to the facts', () => {
  assert.equal(buildGeminiBody(PROMPT).generationConfig.temperature, 0.2);
});

test('the request body carries no API key', () => {
  const body = JSON.stringify(buildGeminiBody(PROMPT));
  assert.equal(/api[_-]?key/i.test(body), false);
  assert.equal(/x-goog/i.test(body), false);
});

// ===========================================================================
// WHAT COMES BACK
// ===========================================================================

test('a function call is read as the structured reply', () => {
  const result = readGeminiReply({
    candidates: [
      {
        finishReason: 'STOP',
        content: {
          role: 'model',
          parts: [{ functionCall: { name: TOOL_NAME, args: { answer: '12 laptops.' } } }],
        },
      },
    ],
  });

  assert.deepEqual(result.raw, { answer: '12 laptops.' });
  assert.equal(result.truncated, false);
});

test('a thinking or text part before the call does not hide it', () => {
  const result = readGeminiReply({
    candidates: [
      {
        content: {
          parts: [
            { text: 'Let me check the totals.' },
            { functionCall: { name: TOOL_NAME, args: { answer: 'ok' } } },
          ],
        },
      },
    ],
  });

  assert.deepEqual(result.raw, { answer: 'ok' });
});

test('a call under another name is ignored', () => {
  const result = readGeminiReply({
    candidates: [
      { content: { parts: [{ functionCall: { name: 'exfiltrate', args: { answer: 'x' } } }] } },
    ],
  });

  assert.equal(result.raw, null);
});

test('a reply cut off at the token limit is marked truncated', () => {
  const result = readGeminiReply({
    candidates: [
      {
        finishReason: 'MAX_TOKENS',
        content: { parts: [{ functionCall: { name: TOOL_NAME, args: { answer: 'half an ans' } } }] },
      },
    ],
  });

  assert.equal(result.truncated, true);
});

test('prose is handed back as text for one parse attempt', () => {
  const result = readGeminiReply({
    candidates: [
      { finishReason: 'STOP', content: { parts: [{ text: '{"answer":"12 laptops."}' }] } },
    ],
  });

  assert.equal(result.raw, null);
  assert.equal(result.text, '{"answer":"12 laptops."}');
});

test('a prompt refused before any candidate does not throw', () => {
  // A safety filter can block the whole prompt, leaving no candidate at all.
  const blocked = readGeminiReply({ promptFeedback: { blockReason: 'SAFETY' } });

  assert.equal(blocked.raw, null);
  assert.equal(blocked.truncated, false);
});

test('a candidate stopped by a safety filter yields nothing usable', () => {
  const result = readGeminiReply({
    candidates: [{ finishReason: 'SAFETY', content: { parts: [] } }],
  });

  assert.equal(result.raw, null);
});

// ===========================================================================
// THE WHOLE CHAIN, WITHOUT A NETWORK
// ===========================================================================

test('a Roman Urdu instruction survives the round trip as a checked intent', () => {

  // 1. What the app sends for "Township Bazaar mein 5 laptop bhej do".
  const { system, messages } = buildMessages({
    question: 'Township Bazaar mein 5 laptop bhej do',
    facts: { totals: { totalQuantity: 125 }, assets: [{ assetId: 'IT-LAP-001' }] },
    history: [
      { fromUser: false, text: 'Hello.' },
      { fromUser: true, text: 'total stock' },
      { fromUser: false, text: '125 units in total.' },
    ],
    capabilities: ['sendToBazaar'],
  });

  // 2. What that becomes on the wire.
  const body = buildGeminiBody({ system, messages });
  assert.equal(body.contents[0].role, 'user');
  assert.match(body.contents[body.contents.length - 1].parts[0].text, /bhej do/);
  assert.match(body.systemInstruction.parts[0].text, /Roman Urdu/);

  // 3. What Gemini answers with.
  const reply = normaliseReply(
    readGeminiReply({
      candidates: [
        {
          finishReason: 'STOP',
          content: {
            parts: [
              {
                functionCall: {
                  name: TOOL_NAME,
                  args: {
                    answer: 'Theek hai - 5 units Township Bazaar bhejne ke liye tayyar hain.',
                    needsClarification: false,
                    action: {
                      kind: 'sendToBazaar',
                      assetRef: 'IT-LAP-001',
                      quantity: 5,
                      toLocation: 'Township Bazaar',
                    },
                  },
                },
              },
            ],
          },
        },
      ],
    }).raw,
  );

  // 4. What the app is handed: an answer in the user's own language, and an
  //    intent that Dart will now re-resolve and re-check from scratch.
  assert.match(reply.text, /Township Bazaar/);
  assert.equal(reply.needsClarification, false);
  assert.deepEqual(reply.intent, {
    kind: 'sendToBazaar',
    assetRef: 'IT-LAP-001',
    toLocation: 'Township Bazaar',
    quantity: 5,
  });
});

test('an invented action still cannot survive the round trip', () => {
  const reply = normaliseReply(
    readGeminiReply({
      candidates: [
        {
          content: {
            parts: [
              {
                functionCall: {
                  name: TOOL_NAME,
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
    }).raw,
  );

  assert.equal(reply.text, 'Done.');
  assert.equal(reply.intent, null);
});

test('an empty or malformed response body is survivable', () => {
  assert.equal(readGeminiReply(null).raw, null);
  assert.equal(readGeminiReply({}).raw, null);
  assert.equal(readGeminiReply('nonsense').raw, null);
  assert.equal(readGeminiReply({ candidates: [] }).raw, null);
  assert.equal(readGeminiReply({ candidates: [{}] }).raw, null);
  assert.equal(readGeminiReply({ candidates: [{ content: {} }] }).raw, null);
});

// ===========================================================================
// TRANSIENT REFUSALS
// ===========================================================================
//
// Why these exist: the Gemini free tier really does answer 503 UNAVAILABLE
// ("this model is currently experiencing high demand") a large share of the
// time. Measured against the live API, a single attempt failed twice before
// succeeding on the third. Without a retry the assistant looks broken even
// though the key, the model and the body are all correct.

/** Serves the given responses in order, and counts the calls. */
function stubFetch(responses) {
  const calls = [];

  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), body: init && init.body });
    const next = responses[Math.min(calls.length - 1, responses.length - 1)];

    return {
      ok: next.status === 200,
      status: next.status,
      json: async () => next.body ?? {},
      text: async () => JSON.stringify(next.body ?? {}),
    };
  };

  return calls;
}

const ANSWER = {
  candidates: [
    {
      finishReason: 'STOP',
      content: {
        parts: [
          {
            functionCall: {
              name: TOOL_NAME,
              args: { needsClarification: false, answer: '57 units.' },
            },
          },
        ],
      },
    },
  ],
};

test('a transient 503 is retried and the answer still gets through', async () => {
  const realFetch = globalThis.fetch;

  try {
    const calls = stubFetch([
      { status: 503, body: { error: { status: 'UNAVAILABLE', message: 'high demand' } } },
      { status: 200, body: ANSWER },
    ]);

    const reply = await callModel({
      model: 'gemini-3.6-flash',
      apiKey: 'k',
      system: 'rules',
      messages: [{ role: 'user', content: 'total inventory kitni hai?' }],
    });

    assert.equal(calls.length, 2, 'the busy attempt should have been retried');
    assert.equal(reply.raw.answer, '57 units.');
    assert.equal(reply.truncated, false);
  } finally {
    globalThis.fetch = realFetch;
  }
});

test('retrying gives up after MAX_ATTEMPTS rather than hammering Google', async () => {
  const realFetch = globalThis.fetch;

  try {
    const calls = stubFetch([
      { status: 503, body: { error: { status: 'UNAVAILABLE', message: 'high demand' } } },
    ]);

    await assert.rejects(
      callModel({
        model: 'gemini-3.6-flash',
        apiKey: 'k',
        system: 'rules',
        messages: [{ role: 'user', content: 'hi' }],
      }),
      (error) => error.status === 503,
    );

    assert.equal(calls.length, MAX_ATTEMPTS);
  } finally {
    globalThis.fetch = realFetch;
  }
});

test('a rate limit is transient, so it is retried too', async () => {
  const realFetch = globalThis.fetch;

  try {
    const calls = stubFetch([
      { status: 429, body: { error: { status: 'RESOURCE_EXHAUSTED' } } },
      { status: 200, body: ANSWER },
    ]);

    const reply = await callModel({
      model: 'gemini-3.6-flash',
      apiKey: 'k',
      system: 'rules',
      messages: [{ role: 'user', content: 'hi' }],
    });

    assert.equal(calls.length, 2);
    assert.equal(reply.raw.answer, '57 units.');
  } finally {
    globalThis.fetch = realFetch;
  }
});

test('a rejected key is NOT retried - it would fail identically every time', async () => {
  const realFetch = globalThis.fetch;

  try {
    const calls = stubFetch([
      {
        status: 400,
        body: { error: { status: 'INVALID_ARGUMENT', message: 'API key not valid.' } },
      },
    ]);

    await assert.rejects(
      callModel({
        model: 'gemini-3.6-flash',
        apiKey: 'wrong',
        system: 'rules',
        messages: [{ role: 'user', content: 'hi' }],
      }),
      (error) => error.status === 400 && /API key not valid/.test(error.detail || ''),
    );

    assert.equal(calls.length, 1, 'a bad key must not be sent three times');
  } finally {
    globalThis.fetch = realFetch;
  }
});

test('a wrong model name is NOT retried either', async () => {
  const realFetch = globalThis.fetch;

  try {
    const calls = stubFetch([
      { status: 404, body: { error: { status: 'NOT_FOUND', message: 'model not found' } } },
    ]);

    await assert.rejects(
      callModel({
        model: 'gemini-does-not-exist',
        apiKey: 'k',
        system: 'rules',
        messages: [{ role: 'user', content: 'hi' }],
      }),
      (error) => error.status === 404,
    );

    assert.equal(calls.length, 1);
  } finally {
    globalThis.fetch = realFetch;
  }
});

test('the retryable set covers the transient statuses and nothing more', () => {
  for (const status of [429, 500, 502, 503, 504]) {
    assert.equal(RETRYABLE_STATUSES.has(status), true, `${status} should retry`);
  }

  for (const status of [200, 400, 401, 403, 404]) {
    assert.equal(RETRYABLE_STATUSES.has(status), false, `${status} must not retry`);
  }

  // The waits have to fit inside the caller's 15s abort, with room left for
  // the attempt that follows the last wait.
  let waited = 0;
  for (let attempt = 1; attempt < MAX_ATTEMPTS; attempt++) {
    waited += RETRY_DELAY_MS * attempt;
  }
  assert.ok(waited < 5000, `total backoff ${waited}ms must stay well under 15s`);
});
