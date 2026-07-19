# Work Agent — Engineering

**Status:** Living. Must always describe reality, never aspiration. Last substantive
change: 2026-07-19.

If this doc and the code disagree, the doc is a bug. Fix it in the increment that
caused the drift.

For *why* a choice was made, read the ADR. This doc says what is true now;
[docs/decisions/](../decisions/) says why and what we rejected.

---

## Current reality

The app runs on a durable three-layer runtime: **AgentKit** (a local Swift package,
ADR-0002/ADR-0006's one deliberate package boundary) under the **Work Agent** macOS app.
A conversation is a `ConversationRecord` (SwiftData, ADR-0008), listed in a sidebar
(FR-071); sending a message drives one durable run through `TaskCoordinator`, streaming
into the message live; a run in flight when the app quits pauses at its next checkpoint
and offers an explicit resume on relaunch (FR-072); the active provider fails over
automatically to a designated fallback mid-run (FR-006), replaying prior turns stripped
of the failed provider's opaque metadata.

The `Experiments/FoundationModelsPOC/` spike from increments 2–3 is gone: its proven
executors, transcript archive, schema bridge, and session-semantics tests migrated into
AgentKit (see `git log` for its history) rather than living on as a second, drifting
implementation.

```
AgentKit/                                    local SPM package (ADR-0002, ADR-0006)
  Package.swift                              name "AgentKit" — working label, not final
  Sources/
    ToolVocabulary/                          ToolAnnotations, effect/budget value types
    RuntimeCore/
      Identifiers.swift                      RunID / AttemptID / ToolInvocationID
      RunEvent.swift                         the append-only journal's event vocabulary
      TranscriptArchive.swift                versioned Transcript persistence + replay
      SchemaBridge.swift                     JSON Schema → GenerationSchema
      RunPolicy.swift                        attempt-ceiling composable limit
      RunJournal.swift                       protocol + FileRunJournal (fsync'd jsonl)
      CheckpointStore.swift                  protocol + FileCheckpointStore (atomic JSON)
      RunStatus.swift                        RunStatus, RunCheckpoint
      InstrumentedTool.swift                 tracing/durable-identity Tool wrapper
      SessionAttempt.swift                   the one place a LanguageModelSession is built
      TaskCoordinator.swift                  durable orchestration + FR-006 failover
    Executors/
      OpenAICompatibleExecutor.swift          9 curated providers, one executor
      AnthropicExecutor.swift                 Anthropic Messages
      StreamParsing.swift                     SSE parsers, both wire formats
    RuntimeTesting/
      ScriptedLanguageModel.swift             closure-scripted LanguageModel double
  Tests/
    RuntimeCoreTests/                         20 tests: durability, failover, semantics
    ExecutorsTests/                           5 tests: SSE parsing, both wire formats

Work Agent/
  Work_AgentApp.swift             App: NSApplicationDelegateAdaptor, ModelContainer
  AppDelegate.swift                pauses in-flight runs before quitting (FR-072)
  Providers/
    ModelRegistry.swift          models.dev types + lenient decoding
    RegistryLoader.swift         bundled snapshot + eager-ish network refresh
    ProviderCatalog.swift        base URLs, auth styles, chat base overrides
    CuratedCatalog.swift         the 11-provider/16-model allowlist (FR-061/062)
    Keychain.swift               the only place keys live (FR-052)
    ProviderStore.swift          configured providers + selected model, persisted
    ProviderVerifier.swift       check a key before reporting it usable (FR-056)
    ChatError.swift              user-facing failure vocabulary (PRODUCT.md §2)
  Settings/
    ProviderSettingsView.swift   list + / − add/remove by key
    AddProviderSheet.swift       pick provider, paste key, verify, add
  Chat/
    Conversation.swift           ChatMessage/ChatRole — wire and display shape
    ConversationRecord.swift     SwiftData @Model (ADR-0008), one per conversation
    ConversationsStore.swift     sidebar selection + create/delete
    RuntimeEnvironment.swift     injects Keychain+registry into AgentKit; owns run
                                 lifetime keyed by conversation (FR-071)
    ChatViewModel.swift          thin per-conversation UI state
    ConversationListView.swift   the sidebar (FR-071)
    ChatView.swift               NavigationSplitView + transcript + composer (FR-068)
  Resources/
    models-dev-snapshot.json     bundled registry (167 providers), refreshed on launch
Work AgentTests/                 45 unit + 5 gated live-smoke tests (through AgentKit)
docs/                            specs
```

## Stack

| | | Why |
|---|---|---|
| Language | Swift, MainActor-default isolation | Native macOS is the point |
| UI | SwiftUI (`@Observable`) | — |
| Tests | swift-testing | ADR-0004 |
| Structure | Work Agent app + one local AgentKit SPM package (RuntimeCore, Executors, ToolVocabulary, RuntimeTesting) | ADR-0002, ADR-0006 |
| App persistence | SwiftData (`ConversationRecord`) | ADR-0008 |
| Distribution | Developer ID, notarized; **App Sandbox off**, Hardened Runtime on | ADR-0003 |
| Provider chat/inference | AgentKit `Executors`, driven by `RuntimeCore.TaskCoordinator` | ADR-0006, ADR-0007 |
| Model registry | models.dev, bundled + refreshed | ADR-0005 |
| Agent runtime (tools/loop) | `TaskCoordinator` above `LanguageModelSession`; durable journal + checkpoints | ADR-0006 |
| Min macOS | **27.0** | NFR-009, ADR-0006 |
| Runtime package platforms | **iOS 27 and macOS 27**, both build and test green | NFR-010, ADR-0006 |

**App Sandbox is off.** The Xcode template enabled it; it blocked all outbound network,
which is fatal for an app whose whole job is calling provider APIs. Disabling it realizes
ADR-0003 (Developer ID precisely *because* the sandbox forbids what the product needs).
Hardened Runtime stays on for notarization. Networking-and-data types are marked
`nonisolated` since the project defaults to MainActor isolation.

## Architecture

The one structural seam ADR-0002 accepts is real now: **AgentKit**. The app never
constructs a `URLRequest` to a model provider directly — it builds a concrete
`LanguageModel` (`OpenAICompatibleModel` or `AnthropicModel`) and hands it, plus tools
and instructions, to `runSessionAttempt`, which is the only place a `LanguageModelSession`
is created. `RuntimeEnvironment` is the app's one integration point: it never imports
Keychain or the registry *into* AgentKit — it resolves both, then injects a plain
`LanguageModel` value. AgentKit itself has no import of SwiftUI, AppKit, the app target,
or a concrete app database (verified: the package has no dependency on the app; the
reverse dependency, app → package, is the only one that exists).

**Run lifetime is keyed by conversation, not by view.** `RuntimeEnvironment` owns a
`[ConversationRecord.id: RunHandle]` map; `ChatViewModel` is a thin, disposable
per-conversation wrapper the view creates and drops as the sidebar selection changes.
Switching conversations never cancels another conversation's in-flight run (FR-071).

**Durability mechanics.** Each `TaskCoordinator.start`/`resume` call: records
`attemptStarted` in the journal, runs one full `LanguageModelSession` cycle (Apple
resolves any internal tool round-trips), commits the resulting `TranscriptArchive` and a
checkpoint on success, or — on failure — automatically retries against a designated
fallback executor with the archive replayed through `TranscriptArchive.replay(to:)`,
which strips the failed provider's opaque metadata (FR-006). A `CancellationError`
(the app quitting, or the user hitting Stop) checkpoints the run as
`.pausedAwaitingResume` rather than losing it (FR-072/FR-073).

**Tool tracing** is `InstrumentedTool<Base>`: any plain `FoundationModels.Tool` gets
durable invocation identity and a registered/started/completed journal trail just by
running through the runtime — no second tool protocol (runtime-api.md §3). Increment 4
ships the wrapper and proves the cycle; no ToolKit product exists yet (increment 5).

## Testing

`swift-testing`, unit and contract. **No UI-test target, now or later.** UI automation
is permanently outside this product's test strategy: it is slow, flaky, and would
dominate increment time without testing the model/provider behavior that matters.

Requirement IDs go in test display names:

```swift
@Test("FR-006: A failed primary attempt fails over to the fallback automatically")
func coordinatorFailsOverAutomatically() async throws { ... }
```

`rg "FR-006"` finds the requirement, the code, and the test. That's the whole scheme —
see [CLAUDE.md](../../CLAUDE.md) § Traceability for why there are no per-requirement
tags.

AgentKit's own suite (`swift test` inside `AgentKit/`) is 25 tests: transcript
round-trips and provider-switch metadata stripping, JSON-Schema→`GenerationSchema`
conversion, `FileRunJournal`/`FileCheckpointStore` durability across a fresh instance
(standing in for a process restart), `TaskCoordinator` success/failover/resume paths
against plain scripted `RunAttemptExecutor` closures (no network needed to prove
durability), `InstrumentedTool` journaling, and the migrated Apple-session-semantics
suite (cancellation, revert-on-failure, concurrent tool scheduling, cross-provider
transcript reconstruction) now built on the reusable `ScriptedLanguageModel` instead of
an ad hoc per-test executor. It builds and passes on both macOS 27 and iOS 27
(`xcodebuild ... -destination 'generic/platform=iOS'`).

**Live smoke tests** (`LiveSmokeTests`, app target) hit real provider APIs through
AgentKit's production executors, gated with `.enabled(if:)` on a `TEST_RUNNER_<VAR>` key
so normal runs skip them.

**Verification gap, named honestly.** The built app was launched and quit cleanly (no
crash, no fault-level log entry) to confirm the SwiftData/sidebar/`AppDelegate` wiring
doesn't break at runtime. The interactive path — send a message, watch it stream, quit
mid-run, relaunch, see the paused banner, click Resume, switch conversations mid-stream —
was not exercised in the running app; screen-control access to drive it was declined.
This is a real gap between "the mechanics are unit-tested" and "a human watched it work."

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

No ToolKit products, no tool selection/approval policy, no MCP — increment 5.
