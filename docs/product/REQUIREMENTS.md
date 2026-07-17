# Work Agent — Requirements

**Status:** Living. Last substantive change: 2026-07-16.

Every requirement here traces to something Toni said, and quotes it. If it doesn't, it
isn't a requirement — it's an open question. See [CLAUDE.md](../../CLAUDE.md)
Non-negotiable 0.

## How to read this

Requirements use [EARS](https://alistairmavin.com/ears/) syntax so each is individually
testable: *The system shall…* (always), *While/When/Where/If…* (conditional).

`FR` = functional, `NFR` = non-functional. **IDs are permanent** — removed requirements
are tombstoned at the bottom and their numbers are never reused.

**Status:** `Specified` (agreed, not built) · `Implemented` (built, tested, traced) ·
`Removed` / `Superseded`.

Everything is `Specified`. The codebase is an Xcode template.

---

## Model neutrality

The product thesis — see [PRODUCT.md](PRODUCT.md) §1. A change that breaks one of these
is a change to what the product is.

| ID | Requirement | Traces to | Status |
|---|---|---|---|
| **FR-001** | The system shall perform all model inference through a provider abstraction, such that no feature depends on a specific model vendor. | "we need to be able to innovate as an app irrespective of the LLMs" | Specified |
| **FR-005** | The system shall allow the user to supply their own credentials for a provider they already have a relationship with. | "ChatGPT subscription can be used with any app" | Specified |
| **FR-006** | If a provider becomes unavailable mid-task, then the system shall preserve task state and allow resumption on another provider. | "task failover cool" | Specified |
| **FR-060** | The system shall expose the full capabilities of each model, including capabilities exclusive to one provider, and shall not restrict a model to a subset common across providers. | "we implement all capabilities any of the models has, even if provider-exclusive… we're not trying to neuter them" | Specified |
| **NFR-001** | Adding a new provider shall not require changes outside its adapter and its registration. | consequence of FR-001 | Specified |

**On FR-060 vs FR-001.** These pull in opposite directions on purpose, and the tension is
the design. FR-001 says the *app* never depends on one vendor. FR-060 says a *model* is
never dumbed down to the lowest common denominator. Both hold: the app works with any
provider; each provider lights up everything it can do. What we never do is delete a
capability because a competitor lacks it.

## Providers and models

| ID | Requirement | Traces to | Status |
|---|---|---|---|
| **FR-050** | The system shall allow the user to configure one or more model providers. | "the user can add one or more LLM providers" | Specified |
| **FR-051** | The system shall present available providers and models from a registry rather than requiring the user to type identifiers. (ADR-0005) | "we should have a register of them… can we use a ready registry" | Specified |
| **FR-061** | The system shall offer only an explicit curated set of models, and shall not present any other model. | "those are the only ones shown in the menu" | Specified |
| **FR-062** | The system shall offer only first-party providers, and shall not present resellers or aggregators. | "let's start with 1P access for now, no resellers for now" | Specified |
| **FR-055** | The system shall allow the user to designate which configured provider and model is used. | implied by "one or more providers" | Specified |
| **FR-057** | The system shall allow the user to remove a configured provider, and shall delete its stored credential when they do. | inferred — standard practice | Specified |
| **FR-052** | The system shall store provider credentials in the macOS Keychain, and shall not write them to preferences, logs, or application state. | inferred — standard practice | Specified |
| **FR-067** | Where a provider is OpenAI, the system shall support both an API key and subscription-based sign-in. | "for GPT, we should support both API key as well as subscription" | Specified — see caveat |
| **FR-056** | When the user supplies a credential, the system shall verify it against the provider before reporting the provider as usable. | inferred — standard practice | Specified |
| **FR-054** | If the model registry cannot be fetched, then the system shall fall back to its bundled snapshot and remain fully usable. (ADR-0005) | inferred — ADR-0005 design | Specified |
| **NFR-007** | Registry decoding shall be lenient: unknown fields ignored, and an entry that fails to decode shall be skipped rather than fail the load. (ADR-0005) | inferred — ADR-0005 design | Specified |
| **NFR-008** | The system shall not block launch on a network request. | inferred — ADR-0005 design | Specified |

The five marked *inferred* are mine, not Toni's. They're standard practice and he's seen
them listed without objection, but they have not been explicitly confirmed.

**Caveat on FR-067 (OpenAI subscription sign-in).** Recorded because Toni asked for it.
The risk is unquantified, and it should not be built without deciding to accept that:

- **OpenAI does not document permission.** Their auth docs describe sign-in for "the
  ChatGPT desktop app, Codex CLI, and IDE extension" — their own products. No partner
  program, no allowlist, no third-party path. That is *absence of stated permission*,
  which is weaker than Anthropic's explicit ban — the two should not be conflated.
- **OpenClaw's docs assert "OpenAI explicitly supports subscription OAuth usage in
  external tools,"** but cite nothing: no OpenAI policy, no announcement, no statement,
  and no risk caveat. A third party asserting another vendor's policy, with a commercial
  interest in it being true, is not evidence of that policy.
- **The precedent runs one way.** Anthropic and Google both closed this path in 2026.

Not a blocker, and Toni's call to make. But FR-067 rests on an unsourced claim, and that
should be visible in the spec rather than discovered later.

### The curated set (FR-061, FR-062)

Toni's list, verbatim. Eleven first-party providers, sixteen models. Every ID verified
against a live `models.dev/api.json` on 2026-07-16; all sixteen report `tool_call: true`.

| Provider | Model IDs | Toni's words |
|---|---|---|
| `openai` | `gpt-5.6`, `gpt-5.6-sol`, `gpt-5.6-luna`, `gpt-5.6-terra` | "GPT-5.6 all variants" |
| `anthropic` | `claude-opus-4-8`, `claude-sonnet-5`, `claude-fable-5` | "fable/opus/sonnet latest" |
| `moonshotai` | `kimi-k3` | "Kimi K3" |
| `xai` | `grok-4.5` | "Grok 4.5" |
| `zai` | `glm-5.2` | "GLM-5.2" |
| `meta` | `muse-spark-1.1` | "Muse Spark 1.1" |
| `google` | `gemini-3.5-flash` | "Gemini 3.5 Flash" |
| `deepseek` | `deepseek-v4-pro` | "Deepseek V4 Pro" |
| `minimax` | `MiniMax-M3` | "Minimax-M3" |
| `thinkingmachines` | `inkling` | "Inkling" |
| `alibaba` | `qwen3.7-max` | "Qwen 3.7 Max" |

All eleven ship together. *"start with all of the ones I said."*

**Note (2026-07-16):** an earlier pass reported Kimi K3, Inkling, and MiniMax-M3 as
absent from the registry, and recommended dropping MiniMax on that basis. That was
wrong — it read a snapshot that had gone stale within about an hour of being fetched.
All three are first-party and present. See
[research/llm-provider-registries.md](../research/llm-provider-registries.md) § staleness.

`thinkingmachines` is worth noting mechanically: it authenticates with `TINKER_API_KEY`
against an OpenAI-compatible endpoint, so it needs no bespoke adapter.

## Traces and their presentation

| ID | Requirement | Traces to | Status |
|---|---|---|---|
| **FR-063** | The system shall persist a complete trace of everything it does, including all details, regardless of what is displayed. | "we store traces of everything… all details are persisted" | Specified |
| **FR-064** | The system shall present traces in the user interface in a legible, user-friendly form. | "showcase them in the UI in a nice UI too" | Specified |
| **FR-065** | The system shall display both model reasoning and tool calls in a user-friendly form, rather than as raw protocol detail. | "both reasoning as well as tool calls should be shown user friendly in the UI" | Specified |
| **FR-066** | The system shall allow the user to turn the display of reasoning traces on or off. | "reasoning traces could be turned on or off in UI by user for now" | Specified |

**Note.** FR-065 reverses the inherited draft, which said to hide reasoning and describe
work as outcomes rather than tool calls. Toni wants the machinery visible — made
friendly, not hidden. FR-063 keeps raw detail regardless of display, so turning reasoning
off (FR-066) is a display choice and never a data loss.

## Non-functional

| ID | Requirement | Traces to | Status |
|---|---|---|---|
| **NFR-003** | The system shall be distributed as a Developer ID–signed, notarized application. (ADR-0003) | Toni's distribution answer | Specified |
| **NFR-005** | Every requirement in this document shall be traceable to code and tests by its ID. | "numbering or coding for requirements and comments in code and test to link to specific requirements" | Specified |
| **NFR-002** | Task state and history shall reside on the Mac. | "a local agent that does work on behalf of the user" | Specified |
| **NFR-006** | The user interface shall remain responsive while a task is running. | inferred | Specified |

---

## Non-goals

Stated, so their absence is a decision:

- **Locally-hosted models. Ever.** *"no local models ever."* The provider abstraction
  must not assume hosted, but no local provider will be built.
- **Resellers and aggregators.** FR-062. *"no resellers for now."*
- **Anthropic subscription authentication.** Anthropic's own docs: OAuth "is intended
  exclusively for Claude Code and Claude.ai," and using Pro/Max tokens "in any other
  product, tool, or service constitutes a violation" — enforced since early 2026 with
  account suspensions. This is a firm ban with a named consequence for *our users*, not
  an ambiguity. OpenAI is a separate and genuinely open question — see FR-067 below.
  Evidence: [research/provider-subscription-auth.md](../research/provider-subscription-auth.md).
- **Specific tool approvals.** *"specific tool approvals will come later."*

## Deliberately unspecified

- **Connections** (Gmail, Drive, M365) — until a real task needs one.
- **Native app control** (Accessibility, screen capture) — ADR-0003 keeps it possible.
- **Automations and scheduling** — post-engine.

---

## Removed and superseded

IDs are permanent and never reused. Most of these were written by an agent from the
inherited `MACOS_FRONTEND_ROADMAP.md` draft, on topics Toni had never raised. That is the
failure CLAUDE.md Non-negotiable 0 now exists to prevent.

| ID | Was | Why removed |
|---|---|---|
| FR-002 | At least two hosted vendors from different vendors | "remove fr-002" |
| FR-003 | Changing provider preserves capabilities | Contradicts FR-060; with full-capability support, switching models *does* change what's available |
| FR-004 | Degrade provider-exclusive features to a neutral implementation | Directly contradicted: "we're not trying to neuter them" |
| FR-007 | Local model treated as an ordinary provider | "no local models ever" — now a non-goal |
| FR-010–FR-013, FR-015 | Durable task model, persistence, status, event recording, stop | From the draft. Toni has not specified a task model. FR-063 covers trace persistence. |
| FR-014 | Preserve partial completion | "I don't know what partial completion means" — explained; not requested |
| FR-016 | Do not present hidden reasoning as progress | Reversed by FR-065/FR-066 — reasoning is shown, toggleable |
| FR-020–FR-025 | Effect-based approval model (6 requirements) | From the draft. "specific tool approvals will come later" |
| FR-030–FR-032 | Activity record, local/cloud split, source inspection | From the draft. FR-063/FR-064 cover what Toni actually asked for |
| FR-040–FR-042 | Hide implementation vocabulary, outcomes over tool calls, advanced surface | From the draft. FR-065 supersedes: show the machinery, made friendly |
| FR-053 | Offer only tool-calling models | Superseded by FR-061 — the curated set is stricter |
| NFR-004 | No arbitrary code execution on the host outside isolation | From the draft. Toni has not raised sandboxing |
