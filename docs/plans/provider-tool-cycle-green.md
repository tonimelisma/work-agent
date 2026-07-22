# Plan: get the provider tool-cycle matrix to green (ROADMAP item 1)

**Written:** 2026-07-21, after a code review of PRs #13 and #14 against the tree.
**Roadmap item:** 1 — "Provider tool-cycle failures — review findings from the
2026-07-20 live matrix".

The 2026-07-20 matrix measured 5 of 11 providers passing a real tool cycle and
ranked five suspects. This plan replaces that ranking with **measured causes**:
every failure was reproduced and isolated live on 2026-07-21 before a line of
this plan was written. Two of the roadmap's five sub-items turned out to be
wrong about the cause, one is confirmed and much bigger than stated, and one is
confirmed with better evidence than the original claim had.

---

## What the diagnosis actually found

### The headline: a class bug in `ExecutorChannelBridge`, reproduced offline

Roadmap item 1.2 guessed minimax + meta shared "a class bug on our side of the
second request". The class bug is real, it is ours, and it is on the **first**
response — and it is far broader than two providers.

**Apple's `LanguageModelSession` throws `"Session ended without producing a
response"` whenever one generation produces both a Response entry and a
ToolCalls entry.** Reproduced with `ScriptedLanguageModel`, no provider
involved, six variants:

| Channel events sent in one generation | Result |
|---|---|
| toolCalls only | **OK** |
| response text → toolCalls | **throws** |
| toolCalls → response text | **throws** |
| response text → toolCalls → `replaceTextSegment("")` | **throws** |
| reasoning → toolCalls | **OK** |
| response-text-sent-as-reasoning → toolCalls | **OK** |

So order does not matter, and there is no undo: Apple's channel exposes only
`response` / `reasoning` / `toolCalls` event factories (verified in the OS 27
`swiftinterface`) and no entry-removal action; `replaceTextSegment("")` leaves
the entry in place.

`ExecutorChannelBridge.channelEvents(for:)` emits `.response(.appendText(…))`
the instant any `delta.content` arrives, then `.toolCalls(…)` when the tool call
arrives. Any provider whose model **narrates before calling a tool** therefore
hard-fails. Raw-wire capture (2026-07-21) shows exactly that:

- **minimax** (`MiniMax-M3`) streams its chain of thought into `delta.content`
  wrapped in `<think>…</think>` *and* duplicates it into `delta.reasoning`,
  then emits the tool call.
- **meta** (`muse-spark-1.1`) streams a plain preamble —
  `"I'll call the sentinel tool now to retrieve the required string."` — then
  emits the tool call.

Both providers' wire traffic is well-formed OpenAI-compatible SSE with a proper
`id`, `name` and JSON `arguments`. Nothing is wrong on their side. This is also
latent for **anthropic**, whose models routinely emit text before `tool_use`;
the 2026-07-20 run passed only because that turn's preamble landed in a thinking
block.

### openai: confirmed, and the Responses wire shape is now captured

Roadmap item 1.1 was right. `gpt-5.6` cannot tool-call on
`/v1/chat/completions` (HTTP 400, "use /v1/responses or set reasoning_effort to
'none'"). The full two-leg cycle was verified live on `/v1/responses` on
2026-07-21 — request → `function_call` → `function_call_output` → final text —
including streaming. The exact shape is recorded in
`research/provider-chat-endpoints.md` under "The OpenAI Responses API"; it is a
genuinely third wire format, so it gets a third executor.

### moonshotai: the roadmap's premise is disproven

Item 1.3 assumed "something in our request body changed the behavior; diff the
working old probe body against the executor's request". Measured:

- Raw `curl` with **four** schema variants (Apple-verbatim including `x-order`
  and `title`; no `x-order`; neither; minimal) — `kimi-k3` called the tool in
  **all four**.
- Dumping the executor's own request body and replaying the live test:
  `kimi-k3` called the tool in **2 of 3** consecutive runs. The failing run
  fabricated a result instead — `"sentinel_tool called successfully. Return
  value: \`sentinel_ok_7f3a2b\`"`, a hallucinated sentinel.

There is no request-body defect. `kimi-k3` is **intermittent**: it sometimes
hallucinates the tool result rather than calling the tool. The correct output is
an honest record, not a code change.

### zai/GLM: account-side, now with discriminating evidence

Item 1.4 said the auth code is right and the rejection is account-side. PR #14's
evidence did not actually support that — the "byte-exact" unit test asserts the
token equals a string the implementation itself produced (determinism, not
conformance), and the `curl` confirmation used the same disputed shape. A
discriminating experiment was run on 2026-07-21 instead, four header variants ×
both hosts:

| Header | `open.bigmodel.cn` | `api.z.ai` |
|---|---|---|
| `{alg, sign_type}` (what we ship) | 401 code **1000** `身份验证失败` | 401 code **1000** `Authentication Failed` |
| `{typ, alg, sign_type}` (PyJWT-style) | 401 code **1000** | 401 code **1000** |
| `{alg, sign_type, typ}` | 401 code **1000** | 401 code **1000** |
| `{typ, alg}` — **`sign_type` removed** | 401 code **401** `令牌已过期或验证不正确` | 401 code **401** `token expired or incorrect` |

Removing `sign_type` produces a *different* error code — the server parses the
JWT and distinguishes a malformed/unverifiable token (401) from a structurally
valid one it declines to authorize (1000). Our token reaches the 1000 branch, so
the shape is accepted and the rejection is account-level. Adding `typ` changes
nothing. **The conclusion stands; it now has evidence.** No code change.

### thinkingmachines: unchanged

`GET /v1/models` with a valid key returns an empty list; `inkling` 400s with
"Tokenizer not supported". Nothing is deployed on the account. No code change.

---

## Requirements

New IDs minted from the measured failures (next-free counters in PRODUCT.md to
be advanced by the implementer):

- **FR-084** — When a provider streams assistant text and a tool call in the
  same generation, the system shall emit only the tool-call transcript entry, so
  that the session runs the tool instead of failing.
- **FR-085** — The system shall support OpenAI's Responses API as a distinct
  executor, completing a request → tool call → tool result → final response
  cycle for models that cannot tool-call on Chat Completions.
- **NFR-011** — When a provider stream ends without producing any assistant
  content, tool call, or reasoning, the system shall fail with a provider-named
  diagnostic rather than an opaque session error.

## Work

### 1. `ExecutorChannelBridge`: never emit a Response entry on a tool-call turn

`Sources/Executors/AnthropicExecutor.swift` (the bridge lives here).

- Add `init(requestID:providerID:toolCallsPossible:)`. Both executors pass
  `!request.enabledToolDefinitions.isEmpty`.
- When `toolCallsPossible == false`, `.response(text)` streams immediately,
  exactly as today — a tool-less chat turn keeps token-by-token streaming.
- When `toolCallsPossible == true`, `.response(text)` **buffers** into
  `pendingResponseText` and emits nothing. There is no earlier signal: in
  OpenAI-compatible SSE the tool call can follow arbitrarily much content, and
  Apple offers no way to retract an entry. Buffering is forced, not chosen.
- Move `.usage` out of the inline path into the completion step, so
  `updateUsage` is never routed to an entry that does not exist yet and the
  response/toolCalls/reasoning routing decision is made with the whole stream in
  view.
- Add `mutating func completionEvents() throws -> [Event]`, called by every
  executor after `consumeEventStream` returns:
  - if a tool call was seen → discard `pendingResponseText` (preamble, not the
    answer) and emit the deferred usage against the tool-calls entry;
  - else if `pendingResponseText` is non-empty → emit
    `.response(.appendText(buffered))` then the deferred usage;
  - else if nothing content-bearing was produced at all → throw
    `ProviderStreamError.event(provider:type:message:)` naming the provider and
    the last `finish_reason` (**NFR-011**). This is what turned two real failures
    into an unreadable Apple error for a day.

Tests (`Tests/ExecutorsTests`, offline, no keys — the `ScriptedLanguageModel`
probe generalizes into permanent coverage):

- text-then-tool-call through a real `LanguageModelSession` completes the tool
  cycle (**FR-084**) — this is the regression test for minimax and meta.
- tool-call-only and text-only turns both still work.
- a tool-less turn streams its text (the buffer is not engaged).
- a stream with only usage/finish throws the named diagnostic (**NFR-011**).

### 2. `OpenAIResponsesExecutor` — the third wire shape (FR-085)

New file `Sources/Executors/OpenAIResponsesExecutor.swift`, plus a
`OpenAIResponsesStreamParser` in `StreamParsing.swift`. A separate executor, not
an `endpointStyle` flag on `OpenAICompatibleExecutor`: the request body, the tool
declaration shape, the conversation-item model and every SSE event name differ.
This is the same reasoning ENGINEERING.md already records for Anthropic under
"Two executors, not eleven" — a distinct wire format earns a distinct executor;
a shared wire format never earns one. It becomes "three executors, not eleven".

Wire shape, verified live 2026-07-21 (record it in the research doc, do not
re-derive):

- `POST /v1/responses`, `Authorization: Bearer`, `stream: true`, `store: false`,
  `include: ["reasoning.encrypted_content"]`.
- Tools are **flat**, not nested under `function`:
  `{"type":"function","name":…,"description":…,"parameters":…}`.
- Input items, not `messages`: `{"role":"user","content":…}`,
  `{"type":"function_call","call_id":…,"name":…,"arguments":…}`,
  `{"type":"function_call_output","call_id":…,"output":…}`, and reasoning items
  `{"type":"reasoning","id":"rs_…","summary":[],"encrypted_content":…}`.
- `tool_choice`: `auto` / `required` / `none`. `reasoning: {"effort": …}` maps
  from `ContextOptions.ReasoningLevel` exactly as the Anthropic executor's
  `effort(for:)` does.
- SSE events (the `type` field inside each `data:` payload):
  `response.output_item.added` (item `type` `reasoning` → capture `id`;
  `function_call` → capture `call_id` + `name`),
  `response.function_call_arguments.delta` → `delta`,
  `response.output_text.delta` → `delta`,
  `response.output_item.done` (**take `encrypted_content` from here — it differs
  from the value on `.added`**), `response.completed` → `response.usage`.
- Reasoning state replays as `openai.reasoning_item` metadata on the reasoning
  entry, namespaced so `TranscriptArchive.replay(to:)` strips it on a provider
  switch by the existing prefix rule. Replaying the reasoning items verbatim on
  leg 2 was verified accepted.

Add `OpenAIResponsesModel: LanguageModel`. Wire the openai live test to it.

### 3. Encoder hardening

`ExecutorRequestEncoding`, both encoders: a tool call whose `arguments.jsonString`
is empty must encode as `{}`. Today `anthropicMessages` feeds it to
`JSONSerialization.jsonObject` and throws, and `openAIMessages` replays an empty
string — meta's API rejects that with HTTP 400 `"arguments must be valid JSON"`.
Unit-test both encoders.

### 4. PR #13 errata — redacted_thinking

Two defects found reviewing PR #13 against the tree; the earlier review passed it
as clean.

- **`redactedThinkingData` is only re-emitted when the incoming event carries the
  redacted key** (`AnthropicExecutor.swift:443`). In a real Anthropic response
  the redacted block (index 0) is followed by the thinking block's
  `thinking_delta`s and a terminal `signature_delta`, each producing a
  `.updateMetadata` **without** the redacted key. Apple's
  `updateMetadata(_ values:)` merge-vs-replace semantics are undocumented and
  unobservable — under replace semantics the redacted payload is silently lost in
  exactly the mixed case the feature exists for. Fix: once any blob is seen,
  include the accumulated JSON in **every** subsequent reasoning metadata update.
  Correct under either semantics.
- **The encoder decodes only the JSON-array form.** A bare string value drops
  silently. Make the decode tolerant: array first, single string as one blob.

Both are unit-testable against the pure accumulation seam and the encoder.

### 5. Records

- `research/provider-chat-endpoints.md` — replace the 2026-07-20 "Open / not
  done" speculation with the 2026-07-21 measured causes: the six-variant channel
  table, the minimax/meta raw-wire excerpts, the moonshot 4-schema + 2-of-3 runs
  result, the GLM four-header discriminating table, and the full Responses API
  shape.
- `PRODUCT.md` — FR-084, FR-085, NFR-011; refresh the provider matrix claim and
  the test count.
- `ENGINEERING.md` — "Three executors, not eleven"; the response/tool-call
  mutual-exclusion rule and *why* buffering is forced (no removal action in the
  channel API); the deferred-usage change.
- `README.md` — the matrix line, once measured post-fix.
- `ROADMAP.md` — item 1 deleted; the two genuinely-Toni items (GLM account,
  thinkingmachines deployment) survive as a short item since they are not ours
  to fix; the moonshot intermittency is recorded, not scheduled.

## Verification

- `swift test` green (offline; the new FR-084/NFR-011 coverage runs unconditionally).
- `xcodebuild` iOS build green.
- `set -a; source .env; set +a; swift test --filter ExecutorsLiveTests` — the
  full eleven-provider matrix, re-measured and re-tabled honestly.

## Expected outcome, stated up front

- **Fixed by this increment:** minimax, meta (bridge class bug); openai
  (Responses executor). Target: **8 of 11**.
- **Intermittent, recorded not fixed:** moonshotai — model-side hallucination,
  ~2 of 3.
- **Not ours:** zai/GLM (account entitlement) and thinkingmachines (nothing
  deployed) stay failed with a Toni action each. 11 of 11 is not reachable from
  this repo.

If the re-measured matrix disagrees with any of this, the table is what ships.
