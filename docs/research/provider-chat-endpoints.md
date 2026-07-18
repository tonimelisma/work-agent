# Provider chat endpoints — what each curated provider actually needs

**Last verified:** 2026-07-17 (every endpoint probed live)
**Why we looked:** Increment 2 streams chat from all eleven curated providers. Guessing
endpoints/paths/auth would mean 404s and 401s discovered mid-UI. Feeds ADR-0006.

---

## Probed live, 2026-07-17

Each was hit with a real key from `.env` and a one-line prompt. "Streams" = HTTP 200 with
an SSE body.

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

## What this settles for the adapters (ADR-0006)

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
than the key used directly. That's a third auth style the current adapters don't
implement. GLM ships in the menu but is unusable until this is built. Not fixed here —
tracked so it isn't rediscovered.

## Open / not done

- **xAI, Meta, Thinking Machines** endpoints unprobed — no keys. All expected
  OpenAI-compatible (Thinking Machines' registry `npm` is `@ai-sdk/openai-compatible`),
  but "expected" is not "confirmed."
- **Exact GLM JWT parameters** (claims, expiry) — not worked out.
- **max_tokens defaults.** The OpenAI adapter sends no token cap (provider default);
  Anthropic requires one, set to 4096. Whether 4096 is a good ceiling is unmeasured.
- **Non-streaming fallback.** Not built; everything assumes SSE.
