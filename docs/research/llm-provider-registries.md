# LLM provider registries

**Last verified:** 2026-07-16 (live API probed, not just docs)
**Why we looked:** The settings UI needs a list of providers and models. Maintaining
that by hand is a treadmill — models ship weekly. Decided in ADR-0005.

---

## models.dev — chosen

[models.dev](https://models.dev) · [anomalyco/models.dev](https://github.com/anomalyco/models.dev) · **MIT** · maintained by the SST team, community PRs

The registry OpenCode uses internally. Contributors submit TOML per provider/model; a
GitHub Action validates against a schema.

### Endpoints

| URL | Contents |
|---|---|
| `https://models.dev/api.json` | Provider-specific data — the one we want |
| `https://models.dev/models.json` | Provider-agnostic model metadata |
| `https://models.dev/catalog.json` | Both combined |
| `https://models.dev/logos/{provider}.svg` | Provider logos |

### Measured, 2026-07-16

| | |
|---|---|
| HTTP | 200, `application/json` |
| Size | 3.18 MB uncompressed |
| Latency | ~160 ms |
| Providers | 166 at 00:27; **167 an hour later** — see staleness below |
| Models | 5,666 |
| Tool-capable (`tool_call: true`) | 4,512 |
| Models missing `tool_call` | **0** — field is universal |
| Models with cost data | 5,268 (93%) |

Tool-capable counts for the majors: openai 46, openrouter 267, google 16, anthropic 14,
groq 7.

### Schema

Provider level — exactly 6 keys, of which 5 are universal across all 166:

```json
{
  "id": "anthropic",
  "name": "Anthropic",
  "env": ["ANTHROPIC_API_KEY"],
  "npm": "@ai-sdk/anthropic",
  "doc": "https://docs.anthropic.com/en/docs/about-claude/models",
  "api": "https://..."   // present on only 142/166 — see gap below
}
```

Model level:

```json
{
  "id": "claude-opus-4-5",
  "name": "Claude Opus 4.5 (latest)",
  "family": "claude-opus",
  "tool_call": true,
  "reasoning": true,
  "reasoning_options": [{"type": "effort", "values": ["low","medium","high"]},
                        {"type": "budget_tokens", "min": 1024}],
  "structured_output": true,
  "attachment": true,
  "temperature": true,
  "open_weights": false,
  "knowledge": "2025-05",
  "release_date": "2025-11-24",
  "modalities": {"input": ["text","image","pdf"], "output": ["text"]},
  "limit": {"context": 200000, "output": 64000},
  "cost": {"input": 5, "output": 25, "cache_read": 0.5, "cache_write": 6.25}
}
```

Models are addressed `providerID/modelID`.

### Staleness: the registry moved under us within an hour

**The most important operational finding here, learned by getting it wrong.**

A snapshot of `api.json` fetched at 00:27 on 2026-07-16 had **166 providers** and did not
contain `moonshotai/kimi-k3`, `minimax/MiniMax-M3`, or `thinkingmachines/inkling` — the
`thinkingmachines` provider did not exist in it at all. A re-fetch roughly an hour later
returned **167 providers** with all three present.

An agent used the stale snapshot to tell Toni those models "aren't in the registry" and
to recommend dropping MiniMax. All of that was false. He checked `catalog.json`, found
them, and was right.

Two lessons, and the second is the one that changes design:

1. **Never answer "does this exist" from a local snapshot.** Re-fetch. The cost is
   160 ms.
2. **A bundled snapshot is a stale floor, not a source of truth.** ADR-0005 framed the
   bundle as "the source of truth at launch," with the network as an improvement. That
   framing is wrong in the direction that matters: the data can be *hours* stale, and
   staleness is silent — a missing model looks exactly like a model that doesn't exist.
   The bundle's job is keeping the app usable offline. The network's job is being right.
   Refresh should be eager, not opportunistic.

`catalog.json` and `api.json` were also compared directly once both were fresh: **167
providers each, identical membership.** `catalog.json` is `{models, providers}` —
258 provider-agnostic model entries plus the same provider tree. There is no
completeness difference between the endpoints. The discrepancy was purely staleness.

### Gaps and risks — the reason this doc exists

**No base URL for the majors.** `anthropic`, `openai`, and `google` have no `.api`
field. Verified directly. The 142 providers that *do* have one are mostly
OpenAI-compatible third parties. The reason: models.dev is built for the Vercel AI SDK
(hence `npm` on every entry), and the SDK's per-provider package hardcodes the majors'
base URLs. **In Swift we get no such package, so we hardcode base URLs for the majors
ourselves.** The registry is a catalog, not a connection config.

**`env` names an environment variable, not a credential store.** It tells us the
conventional var name (`ANTHROPIC_API_KEY`), which is useful as a label and for
importing an existing env var. Keys go in Keychain regardless.

**No API versioning or stability guarantee.** Not documented, and we asked. The schema
can shift under us with no notice. Mitigations in ADR-0005: bundle a snapshot, treat
the network copy as a cache, decode leniently, never let a registry change break launch.

**3.18 MB is too big to fetch on every launch.** Needs caching. Also too big to parse
naively on the main thread.

**`npm` and AI SDK orientation are irrelevant to us** but signal where the project's
attention is. If the AI SDK's needs and ours diverge, the registry follows the AI SDK.

---

## Alternatives considered

**[LiteLLM `model_prices_and_context_window.json`](https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json)** — Large, well-maintained, MIT, 100+ providers. Pricing and context focused. Rejected: it's a byproduct of the LiteLLM Python proxy rather than a standalone registry, the shape is oriented to LiteLLM's internals, and it carries known staleness — [39 OpenRouter models in the JSON no longer exist upstream](https://github.com/BerriAI/litellm/issues/20521), [models with missing pricing](https://github.com/BerriAI/litellm/issues/22609). Weaker capability metadata than models.dev.

**[OpenRouter models API](https://openrouter.ai/api/v1/models)** — Live, accurate, no staleness because it's the source of truth for what OpenRouter serves. Rejected as *the* registry: it only describes OpenRouter's own catalog. Using it would mean routing everything through OpenRouter, which is a real product decision (one vendor between us and every model) and the opposite of the neutrality thesis. Still a good option to *offer* as a provider.

**[openmodels](https://github.com/openmodelsrun/openmodels)** — Newer, positions as infrastructure for discovering and comparing models. Not investigated in depth; models.dev satisfied the need first. Revisit only if models.dev degrades.

**Hand-maintained list in-repo** — Zero dependency, full control, no schema risk. Rejected: a treadmill. Models ship weekly and a stale list is a user-visible bug. Note we end up hand-maintaining base URLs for the majors regardless — the gap above — so this is a difference of degree, not kind.

---

## Open / not investigated

- **Whether `tool_call: true` is trustworthy per model.** We take the registry's word.
  Nothing verified against real provider behavior. Given tool calling is the crux of
  the neutrality thesis, an incorrect `true` here is a user-visible failure. Worth
  spot-checking when tools land.
- **Update cadence and lag** for new model releases. Unmeasured. If it lags badly, the
  bundled-snapshot-plus-refresh design absorbs it, but the UI would show stale models.
- **Whether `cost` units are consistent** across providers (assumed USD per million
  tokens — not verified).
- **`models.json`** shape. `api.json` and `catalog.json` have now both been probed and
  match; `models.json` has not.
