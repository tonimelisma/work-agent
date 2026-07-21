# Provider chat endpoints — what each curated provider actually needs

**Last verified:** 2026-07-20 (full tool-cycle probe, all eleven providers, real keys)
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

ROADMAP item 2: every provider driven through a real `LanguageModelSession` with a tool
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

**5 of 11 pass live tool-cycles as of 2026-07-20:** deepseek, anthropic, google, alibaba,
xai. The other six connect (endpoint and auth are right) but fail at the tool-cycle step for
provider-specific reasons named above — recorded honestly rather than narrowed back to a
bare connectivity check to call it green. Fixing any of these beyond GLM's auth is out of
this increment's scope (ROADMAP item 2's plan); each is a candidate for its own future
roadmap item if it matters.

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
constructed JWT, ruling out a package-side encoding bug. Per the bounded-retry plan (two
endpoints, no thrashing further), GLM stays failed. Whatever Zhipu actually wants beyond
this documented community shape (a different claim set, a different signing key derivation,
an account-side activation step) is unknown and would need Zhipu's own current docs or
support to resolve — next time this is picked up, start there rather than re-deriving the
JWT shape, which is now confirmed correct-but-insufficient.

## Open / not done

- **GLM auth beyond the JWT shape** — see above; the *shape* is built and confirmed
  correctly constructed, but the provider still 401s. Unresolved.
- **moonshotai, openai, minimax, meta, thinkingmachines tool-cycle failures** (2026-07-20,
  see the table above) — each fails for a different provider-specific reason (ignored
  tool_choice, an endpoint that plain doesn't support tool calling, an opaque session
  termination, an undeployed model). None investigated further; out of ROADMAP item 2's
  scope, each a candidate for its own future item.
- **max_tokens defaults.** The OpenAI adapter sends no token cap (provider default);
  Anthropic requires one, set to 4096. Whether 4096 is a good ceiling is unmeasured.
- **Non-streaming fallback.** Not built; everything assumes SSE.
