# Work Agent — Engineering

**Status:** Living. Must always describe reality, never aspiration. Last substantive
change: 2026-07-18.

If this doc and the code disagree, the doc is a bug. Fix it in the increment that
caused the drift.

For *why* a choice was made, read the ADR. This doc says what is true now;
[docs/decisions/](../decisions/) says why and what we rejected.

---

## Current reality

The app runs, streams chat from real providers, and stores keys in the Keychain. As of
increment 2:

```
Work Agent/
  Work_AgentApp.swift            App: WindowGroup { ChatView } + Settings scene
  Providers/
    ModelRegistry.swift          models.dev types + lenient decoding
    RegistryLoader.swift         bundled snapshot + eager-ish network refresh
    ProviderCatalog.swift        base URLs, auth styles, chat base overrides
    CuratedCatalog.swift         the 11-provider/16-model allowlist (FR-061/062)
    Keychain.swift               the only place keys live (FR-052)
    ProviderStore.swift          configured providers + selected model, persisted
    ProviderVerifier.swift       check a key before reporting it usable (FR-056)
    ChatProvider.swift           the streaming seam (FR-001) + factory + SSE helper
    OpenAICompatibleChatProvider.swift   10 providers
    AnthropicChatProvider.swift          Anthropic Messages
  Settings/
    ProviderSettingsView.swift   list + / − add/remove by key
    AddProviderSheet.swift       pick provider, paste key, verify, add
  Chat/
    Conversation.swift           ChatMessage / Conversation (persisted, FR-063)
    ChatViewModel.swift          drives streaming, persistence, reasoning toggle
    ChatView.swift               transcript + composer (FR-068)
  Resources/
    models-dev-snapshot.json     bundled registry (167 providers), refreshed on launch
Work AgentTests/                 45 unit + 5 gated live-smoke tests
docs/                            specs
```

## Stack

| | | Why |
|---|---|---|
| Language | Swift, MainActor-default isolation | Native macOS is the point |
| UI | SwiftUI (`@Observable`) | — |
| Tests | swift-testing | ADR-0004 |
| Structure | Single app target, monolith | ADR-0002 |
| Distribution | Developer ID, notarized; **App Sandbox off**, Hardened Runtime on | ADR-0003 |
| Provider chat | Two adapters behind `ChatProvider` | ADR-0007 |
| Model registry | models.dev, bundled + refreshed | ADR-0005 |
| Agent runtime (tools/loop) | **Undecided** | ADR-0006, deferred |
| Min macOS | **Undecided** (project targets 27.0 by template default) | Nothing forces it yet |

**App Sandbox is off.** The Xcode template enabled it; it blocked all outbound network,
which is fatal for an app whose whole job is calling provider APIs. Disabling it realizes
ADR-0003 (Developer ID precisely *because* the sandbox forbids what the product needs).
Hardened Runtime stays on for notarization. Networking-and-data types are marked
`nonisolated` since the project defaults to MainActor isolation.

## Architecture

Still a monolith (ADR-0002). One structural seam exists, and it's the one the thesis
demands: **all inference goes through `ChatProvider`** (FR-001). Two adapters sit behind
it — OpenAI-compatible (ten providers) and Anthropic — chosen by a factory keyed on
provider id (ADR-0007). The UI and view models never know which adapter answered.

Data flows one way: `ProviderStore` (what's configured, key in Keychain) and
`RegistryLoader` (what models exist) feed the views; `ChatViewModel` resolves the selected
model to an adapter, streams chunks, and persists the conversation. No package boundaries
yet — they earn their existence by hurting first.

The agent loop, tools, and orchestration are **not** here — that's ADR-0006. What exists
is plain streaming chat.

## Testing

`swift-testing`, unit and contract. No XCUITest while the UI churns — it would dominate
increment time and tell us little.

Requirement IDs go in test display names:

```swift
@Test("FR-070: content deltas assemble into the reply")
func assemblesContent() async throws { ... }
```

`rg "FR-070"` finds the requirement, the code, and the test. That's the whole scheme —
see [CLAUDE.md](../../CLAUDE.md) § Traceability for why there are no per-requirement
tags.

**Live smoke tests** (`LiveSmokeTests`) hit real provider APIs, gated with
`.enabled(if:)` on a `TEST_RUNNER_<VAR>` key so normal runs skip them. They're how we
prove the adapter code — not just its unit fixtures — actually streams from a real
provider. Network stubbing for unit tests uses `URLProtocol` subclasses; suites that
share one serialize (`.serialized`) so they don't race its static handler.

Tests are necessary and not sufficient. The DOD asks whether the deliverable was
actually run, because a green suite over a feature nobody exercised is how agents
convince themselves of things that aren't true.

## Conventions

- Requirement references at the point of satisfaction: `// REQ: FR-001 — <what and why>`.
  On the code that satisfies it, not on the file.
- Comments state constraints the code can't. Not what the next line does.
- No implementation vocabulary in user-facing strings (PRODUCT.md §2).

## Deferred, and why it's not here

No CI, no linter, no logging framework, no error taxonomy. Each is a real need, and
each is a decision better made with code to point at. They land in the increment that
needs them, with an ADR if there's a genuine alternative.
