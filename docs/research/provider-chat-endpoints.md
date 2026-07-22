# Provider chat endpoints — what each curated provider actually needs

**Last verified:** 2026-07-21 (full tool-cycle probe re-run after the FR-084/FR-085
fixes; **9 of 11 pass**, four consecutive runs)
**Why we looked:** Increment 2 streams chat from all eleven curated providers. Guessing
endpoints/paths/auth would mean 404s and 401s discovered mid-UI. Feeds ADR-0007.

---

## Probed live, 2026-07-17 (connectivity/streaming only)

Each was hit with a real key from `.env` and a one-line prompt. "Streams" = HTTP 200 with
an SSE body. Superseded by the full tool-cycle probe below for the providers that then had
keys; kept as the historical record of what a bare connectivity check found.

| Provider | Chat endpoint | Auth | Result |
|---|---|---|---|
| anthropic | `api.anthropic.com/v1/messages` | `x-api-key` + `anthropic-version` | **200 streams** |
| google | `generativelanguage.googleapis.com/v1beta/openai/chat/completions` | `Authorization: Bearer` | **200 streams** |
| moonshotai | `api.moonshot.ai/v1/chat/completions` | Bearer | **200 streams** |
| deepseek | `api.deepseek.com/chat/completions` | Bearer | **200 streams** |
| alibaba | `dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions` | Bearer | **200 streams** |
| openai | `api.openai.com/v1/chat/completions` | Bearer | 429 — valid key, **no quota** |
| minimax | `api.minimax.io/v1/chat/completions` | Bearer | 402 — valid key, **no balance** |
| zai (GLM) | `api.z.ai/api/paas/v4/chat/completions` **and** `open.bigmodel.cn/…` | Bearer | **401 both** |
| xai | (not probed — no key) | Bearer | — |
| meta | (not probed — no key) | Bearer | — |
| thinkingmachines | (not probed — no key) | Bearer | — |

## Probed live, 2026-07-20 (full tool-cycle, `ExecutorsLiveTests`)

Every provider driven through a real `LanguageModelSession` with a tool
(`SentinelTool`) — a request, a tool call, a second request replaying the tool result, a
final text response — not just a first streamed token. Endpoint and model per provider are
in `Tests/ExecutorsLiveTests/ProviderMatrixTests.swift`.

| Provider | Endpoint | Model | Result |
|---|---|---|---|
| deepseek | `api.deepseek.com/chat/completions` | `deepseek-v4-pro` | **Pass** |
| anthropic | `api.anthropic.com/v1/messages` | `claude-sonnet-5` | **Pass** |
| google | `generativelanguage.googleapis.com/v1beta/openai/chat/completions` | `gemini-3.5-flash` | **Pass** |
| alibaba | `dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions` | `qwen3.7-max` | **Pass** |
| xai | `api.x.ai/v1/chat/completions` (first-ever probe) | `grok-4.5` | **Pass** |
| moonshotai | `api.moonshot.ai/v1/chat/completions` | `kimi-k3` | **Fails** — connects and streams, but ignores the instruction to call the tool under default (auto) `tool_choice`, replying `"OK"` / `"<system>Success.</system>"` instead |
| openai | `api.openai.com/v1/chat/completions` | `gpt-5.6` | **Fails** — HTTP 400: `"Function tools with reasoning_effort are not supported for gpt-5.6 in /v1/chat/completions. To use function tools, use /v1/responses or set reasoning_effort to 'none'."` The Chat Completions surface this package targets does not support tool calling for this model at all |
| minimax | `api.minimax.io/v1/chat/completions` | `MiniMax-M3` | **Fails** — connects, but the session ends with Apple's `"Session ended without producing a response"` after the tool call; reproducible standalone, not a concurrency artifact |
| zai (GLM) | `open.bigmodel.cn/api/paas/v4/…` and `api.z.ai/api/paas/v4/…` | `glm-5.2` | **Fails** — both hosts return `401 {"error":{"code":"1000","message":"Authentication Failed"}}` even with a well-formed HS256 JWT built exactly per the documented community shape (`OpenAICompatibleExecutor.Configuration.AuthStyle.zhipuJWT`, confirmed independently via a standalone `curl` outside the package). GLM's auth requirement is now built and unit-tested; the *provider* still rejects it — see "The Zhipu/GLM wrinkle" below |
| meta | `api.meta.ai/v1/chat/completions` (first-ever probe) | `muse-spark-1.1` | **Fails** — connects, but the session ends with `"Session ended without producing a response"` after the tool call, same symptom as MiniMax |
| thinkingmachines | `tinker.thinkingmachines.dev/services/tinker-prod/oai/api/v1/chat/completions` (first-ever probe) | `inkling` | **Fails** — HTTP 400: `"Model 'inkling' is not supported: Tokenizer not supported for model inkling"`. `GET .../v1/models` with the same key returns an empty list — nothing is currently deployed on this account, despite `inkling` being the model models.dev's registry lists |

**5 of 11 passed as of 2026-07-20.** Superseded by the 2026-07-21 diagnosis below,
which found that **four of those six failures were ours, not the providers'**. Kept as
the record of what the symptoms looked like before the cause was known.

## Diagnosed and re-measured, 2026-07-21 — **9 of 11**

Each 2026-07-20 failure was reproduced and isolated before anything was changed.

| Provider | Result | What changed |
|---|---|---|
| deepseek, anthropic, google, alibaba, xai | **Pass** | unchanged |
| minimax `MiniMax-M3` | **Pass** | FR-084 — our bug, below |
| meta `muse-spark-1.1` | **Pass** | FR-084 — our bug, below |
| openai `gpt-5.6` | **Pass** | FR-085 — moved to `/v1/responses` |
| moonshotai `kimi-k3` | **Pass**, intermittent | nothing; see below |
| zai (GLM) `glm-5.2` | **Fails** — 401 code 1000 | account-side; **Toni action** |
| thinkingmachines `inkling` | **Fails** — HTTP 400, nothing deployed | account-side; **Toni action** |

Four consecutive full-matrix runs on 2026-07-21: 9 pass, the same 2 fail, no flapping.

### The class bug: a Response entry and a ToolCalls entry cannot coexist

Apple's `LanguageModelSession` throws **"Session ended without producing a response"**
whenever one generation produces both a Response entry and a ToolCalls entry. Measured
with `ScriptedLanguageModel`, no provider involved:

| Channel events in one generation | Result |
|---|---|
| toolCalls only | **OK** |
| response text → toolCalls | **throws** |
| toolCalls → response text | **throws** |
| response text → toolCalls → `replaceTextSegment("")` | **throws** |
| reasoning → toolCalls | **OK** |
| the same text sent as reasoning → toolCalls | **OK** |

Order is irrelevant and there is no undo: the OS 27 `swiftinterface` exposes only
`response` / `reasoning` / `toolCalls` event factories and no entry-removal action, and
`replaceTextSegment("")` leaves the entry in place. Hence the buffer in
`ExecutorChannelBridge` (FR-084) — assistant text is withheld while a tool call is still
possible and discarded if one arrives.

Raw wire, captured 2026-07-21, showing why exactly these two providers tripped it:

- **minimax** streams its chain of thought through `delta.content` wrapped in
  `<think>…</think>` *and* duplicates it into `delta.reasoning`, then emits the tool
  call. Its tool call is well-formed (`id`, `name`, then `arguments` as a separate
  delta frame — the `id`/`name` arrive on the first frame only, which the parser
  already carries forward per index).
- **meta** streams a plain preamble — `"I'll call the sentinel tool now to retrieve
  the required string."` — then the tool call. Its `arguments` are sometimes empty
  (`""`) rather than `{}`; replaying that verbatim earns
  `HTTP 400 "arguments must be valid JSON"` from Meta's own API, which is why both
  encoders now normalize an empty argument string to `{}`.

Nothing was wrong on either provider's side. This was also **latent for Anthropic**,
whose models routinely emit text before `tool_use`; 2026-07-20 passed only because that
turn's preamble happened to land in a thinking block.

### moonshotai: intermittent model behavior, not a wire problem

The 2026-07-20 record blamed our request body. Measured otherwise:

- Raw `curl`, four schema variants — Apple-verbatim (including the `x-order` and
  `title` keys `GenerationSchema` emits), no `x-order`, neither, and minimal —
  `kimi-k3` called the tool in **all four**.
- The executor's own request body, dumped and replayed: tool called in **2 of 3**
  runs pre-fix, **4 of 4** post-fix. The one failing run fabricated a result rather
  than calling the tool: `"sentinel_tool called successfully. Return value:
  \`sentinel_ok_7f3a2b\`"` — a hallucinated sentinel.

So `kimi-k3` sometimes hallucinates the tool result instead of calling the tool. Small
sample; treat moonshotai as **intermittent**, and don't read a red moonshot run as a
regression without re-running it.

### The OpenAI Responses API (FR-085)

`gpt-5.6` cannot tool-call on `/v1/chat/completions` at all, and the API's own advice —
set `reasoning_effort` to `'none'` — would neuter the model. `/v1/responses` works;
the full two-leg cycle was verified live 2026-07-21. It is a third wire shape:

- `POST /v1/responses`, `Authorization: Bearer`, `stream: true`.
- `store: false` plus `include: ["reasoning.encrypted_content"]` keeps conversation
  state off OpenAI's servers, which makes replaying reasoning items mandatory.
- **Tools are flat**, not nested under `function`:
  `{"type":"function","name":…,"description":…,"parameters":…}`.
- **`input` items, not `messages`**: `{"role":"user","content":…}`,
  `{"type":"function_call","call_id":…,"name":…,"arguments":…}`,
  `{"type":"function_call_output","call_id":…,"output":…}`, and reasoning items
  `{"type":"reasoning","id":"rs_…","encrypted_content":…}` replayed verbatim
  (confirmed accepted).
- `tool_choice`: `auto` / `required` / `none`; `reasoning: {"effort": …}`;
  `max_output_tokens`; system text goes in `instructions`, not an item.
- SSE events (the `type` inside each `data:` payload):
  `response.output_item.added` (item `function_call` → `call_id` + `name`),
  `response.function_call_arguments.delta` → `delta`,
  `response.output_text.delta` → `delta`, `response.output_item.done`,
  `response.completed` → `response.usage.{input,output}_tokens`.
- **Take reasoning `encrypted_content` from `response.output_item.done`, not from
  `.added`** — the two carry *different* values for the same item id, and only the
  `.done` one round-trips. Measured; this is the kind of thing that costs an hour.
- The server rewrites the schema it is given: it coerced our `"required": []` to
  `"required": ["note"]` and set `"strict": true`. It accepted `x-order` and `title`
  unchanged.

## What this settles for the adapters (ADR-0007)

- **The OpenAI wire format is a de facto standard.** Ten of eleven speak
  `POST {base}/chat/completions`, `stream:true`, SSE, bearer auth. One adapter covers them.
- **Anthropic is the exception** — `/v1/messages`, event-typed SSE, `x-api-key`. Its own
  adapter.
- **Two base-URL overrides** are needed because the registry's `api` isn't the
  OpenAI-compatible surface:
  - `google` — registry `api` is native Gemini; the OpenAI-compatible endpoint is under
    `/v1beta/openai`. Confirmed it accepts `Authorization: Bearer <GOOGLE_API_KEY>`.
  - `minimax` — registry `api` is `…/anthropic/v1` (Anthropic-shaped!); the
    OpenAI-compatible endpoint is `…/v1`. Using `/v1` keeps MiniMax on the common adapter.
- **DeepSeek's base has no `/v1`** — the path is `api.deepseek.com/chat/completions`.

## Reasoning field names differ

The reasoning/thinking delta is not standardized:

- DeepSeek, Alibaba (OpenAI-compatible): `choices[].delta.reasoning_content`
- Others (OpenAI-compatible): `choices[].delta.reasoning`
- Anthropic: `content_block_delta` with `delta.type == "thinking_delta"`, field `thinking`
- Google (via OpenAI-compat) puts a `thought_signature` under `extra_content.google` —
  not human-readable reasoning; we read only `delta.content` for text.

The OpenAI adapter accepts `reasoning_content ?? reasoning`. Tolerate absence.

## The Zhipu/GLM wrinkle

GLM's key (`id.secret` format) is **rejected as a raw bearer token at both** `api.z.ai`
and `open.bigmodel.cn` (`401 / 身份验证失败`). This matches Zhipu's long-standing quirk of
requiring a **JWT signed (HS256) from the id and secret**, with a short expiry, rather
than the key used directly — a third auth style, now built
(`OpenAICompatibleExecutor.Configuration.AuthStyle.zhipuJWT`: split at the first `.`,
header `{"alg":"HS256","sign_type":"SIGN"}`, payload `{"api_key": id, "exp": now+1h(ms),
"timestamp": now(ms)}`, HMAC-SHA256 via CryptoKit, base64url unpadded), unit-tested against
an exact expected token string for a fixed clock and key.

**2026-07-20: still rejected even with a well-formed JWT.** Both hosts return
`401 {"error":{"code":"1000","message":"Authentication Failed"}}` — confirmed twice, once
through the package's live test and once via a standalone `curl` with an independently
constructed JWT, ruling out a package-side encoding bug.

**2026-07-21: confirmed account-side, by a discriminating experiment.** The evidence above
did not actually separate "our token shape is wrong" from "the account is not entitled" —
the unit test asserts the token equals a string the implementation itself produced
(determinism, not conformance), and the `curl` used the same disputed shape. Four header
variants were run against both hosts instead:

| JWT header | `open.bigmodel.cn` | `api.z.ai` |
|---|---|---|
| `{alg, sign_type}` — what we ship | 401 code **1000** `身份验证失败` | 401 code **1000** `Authentication Failed` |
| `{typ, alg, sign_type}` — PyJWT's default shape | 401 code **1000** | 401 code **1000** |
| `{alg, sign_type, typ}` | 401 code **1000** | 401 code **1000** |
| `{typ, alg}` — **`sign_type` removed** | 401 code **401** `令牌已过期或验证不正确` | 401 code **401** `token expired or incorrect` |

Dropping `sign_type` produces a *different* error code, so the server parses the token and
distinguishes a malformed/unverifiable one (**401**) from a structurally valid, correctly
signed one it declines to authorize (**1000**). Ours lands in the 1000 branch, same as the
raw bearer token. Adding `typ: JWT` changes nothing. **The token shape is right; the
rejection is at the account or key-entitlement level.** Next step is Zhipu's console or
support — not another round of JWT archaeology.

## Open / not done

- **GLM's account entitlement** — the token shape is settled (above); the 401/1000 is
  account-side and needs Zhipu's console or support. Nothing left to build here.
- **thinkingmachines has nothing deployed** — `GET /v1/models` returns an empty list with
  a valid key. Needs the account, not code.
- **Streaming is buffered on tool-enabled turns** (FR-084). Assistant text cannot be sent
  until the stream proves no tool call is coming, because Apple's channel offers no way to
  remove an entry. Turns with no tools enabled still stream unbuffered. If Apple ever adds
  an entry-removal or "convert to tool call" action, this buffer can go.
- **Apple emits non-standard schema keys** — `GenerationSchema` encodes `x-order` and
  `title` alongside standard JSON Schema, and we forward them verbatim. Measured harmless
  on moonshotai (4 schema variants, all tool-called) and OpenAI Responses (accepted, then
  rewritten server-side). Not measured on every provider; revisit if one rejects a tool.
- **max_tokens defaults.** The OpenAI adapter sends no token cap (provider default);
  Anthropic requires one, set to 4096. Whether 4096 is a good ceiling is unmeasured.
- **Non-streaming fallback.** Not built; everything assumes SSE.
