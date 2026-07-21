# Work Agent — Engineering

**Status:** Living. Must always describe reality, never aspiration. Last substantive
change: 2026-07-20.

If this doc and the code disagree, the doc is a bug. Fix it in the increment that
caused the drift.

This doc says what is true now AND why it was decided that way -- the rationale for
every structural choice lives in "Why it is built this way" below (app-side
rationale: docs/app/APP.md). There is no separate decisions log.

---

## Current reality

The app runs on a durable three-layer runtime: **AgentKit** (a local Swift package,
the one deliberate package boundary; rationale in "Why it is built this way" below) under the **Work Agent** macOS app.
A conversation is a `ConversationRecord` (SwiftData; rationale in docs/app/APP.md), listed in a sidebar
(FR-071); sending a message drives one durable run through `TaskCoordinator`, streaming
into the message live; a run in flight when the app quits pauses at its next checkpoint
and offers an explicit resume on relaunch (FR-072); the active provider fails over
automatically to a designated fallback mid-run (FR-006), replaying prior turns stripped
of the failed provider's opaque metadata.

Every run also carries the increment-5 starter tools: six file tools (`read_file`,
`list_folder`, `find_files`, `search_files`, `write_file`, `edit_file`) and `fetch_url`,
ungated ("permissions come later") and rooted at the user's home directory.
`ask_user`, `update_plan`, and `web_search` are built and tested as ToolKit products
but not yet wired into the app — the first two need UI that doesn't exist yet
(a question card, a plan display); the third's Brave Search API key arrived
2026-07-19 — live verification is queued (ROADMAP item 3).

The `Experiments/FoundationModelsPOC/` spike from increments 2–3 is gone: its proven
executors, transcript archive, schema bridge, and session-semantics tests migrated into
AgentKit (see `git log` for its history) rather than living on as a second, drifting
implementation.

```
AgentKit/                                    local SPM package (see Why below)
  Package.swift                              name "AgentKit" — working label, not final
  Sources/
    ToolVocabulary/                          ToolAnnotations, effect/budget value types
    Recorder/
      Identifiers.swift                      RunID / AttemptID / ToolInvocationID
      RunEvent.swift                         the append-only journal's event vocabulary
      TranscriptArchive.swift                versioned Transcript persistence + replay
      SchemaBridge.swift                     JSON Schema → GenerationSchema
      RunJournal.swift                       protocol + FileRunJournal (fsync'd jsonl)
      CheckpointStore.swift                  protocol + FileCheckpointStore (atomic JSON)
      RunStatus.swift                        RunStatus, RunCheckpoint
      InstrumentedTool.swift                 tracing/durable-identity Tool wrapper (internal)
      RecorderStore.swift                    read/append façade — item 4's cost-display API
    Executors/
      OpenAICompatibleExecutor.swift          9 curated providers, one executor
      AnthropicExecutor.swift                 Anthropic Messages
      StreamParsing.swift                     SSE parsers, both wire formats
    RuntimeTesting/
      ScriptedLanguageModel.swift             closure-scripted LanguageModel double
    ToolKitFiles/                             read_file, list_folder, find_files,
                                               search_files, write_file, edit_file
    ToolKitWeb/                               fetch_url, web_search (Brave-backed),
                                               NetworkSafety (SSRF host check)
    ToolKitInteraction/                       ask_user, update_plan
    ToolKitForMac/                            umbrella: re-exports the three above
  Tests/
    RecorderTests/                            16 tests: durability, semantics
    ExecutorsTests/                           5 tests: SSE parsing, both wire formats
    ToolKitFilesTests/                        27 tests: paging, docx, glob, read-before-write
    ToolKitWebTests/                          13 tests: Markdown rendering, SSRF, search
    ToolKitInteractionTests/                  6 tests: ask_user/update_plan validation

Work Agent/
  Work_AgentApp.swift             App: NSApplicationDelegateAdaptor, ModelContainer
  AppDelegate.swift                pauses in-flight runs before quitting (FR-072)
  Runtime/
    TaskCoordinator.swift          durable orchestration + FR-006 failover (app-internal)
    RunPolicy.swift                 attempt-ceiling composable limit (app-internal)
    SessionAttempt.swift            the one place a LanguageModelSession is built
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
    ConversationRecord.swift     SwiftData @Model (APP.md), one per conversation
    ConversationsStore.swift     sidebar selection + create/delete
    RuntimeEnvironment.swift     injects Keychain+registry into AgentKit; owns run
                                 lifetime keyed by conversation (FR-071)
    ChatViewModel.swift          thin per-conversation UI state
    ConversationListView.swift   the sidebar (FR-071)
    ChatView.swift               NavigationSplitView + transcript + composer (FR-068)
  Resources/
    models-dev-snapshot.json     bundled registry (167 providers), refreshed on launch
Work AgentTests/                 50 unit + 5 gated live-smoke tests (through AgentKit)
docs/                            specs
```

## Stack

| | | Why |
|---|---|---|
| Language | Swift, MainActor-default isolation | Native macOS is the point |
| UI | SwiftUI (`@Observable`) | — |
| Tests | swift-testing | Why below |
| Structure | Work Agent app + one local AgentKit SPM package (Recorder, Executors, ToolVocabulary, RuntimeTesting) | Why below |
| App persistence | SwiftData (`ConversationRecord`) | docs/app/APP.md |
| Distribution | Developer ID, notarized; **App Sandbox off**, Hardened Runtime on | docs/app/APP.md |
| Provider chat/inference | AgentKit `Executors`, driven by the app's `TaskCoordinator` | Why below |
| Model registry | models.dev, bundled + refreshed | docs/app/APP.md |
| Agent runtime (tools/loop) | `TaskCoordinator` above `LanguageModelSession`; durable journal + checkpoints | Why below |
| Min macOS | **27.0** | NFR-009, Why below |
| Runtime package platforms | **iOS 27 and macOS 27**, both build and test green | NFR-010, Why below |
| Tools | `ToolKitFiles`, `ToolKitWeb`, `ToolKitInteraction`, umbrella'd as `ToolKitForMac` | FR-074–083, tool-architecture.md |
| Tool dependencies | ZIPFoundation (.docx is a zip), SwiftSoup (HTML→Markdown) — the only two external dependencies anywhere in AgentKit, both pre-approved pure Swift | tool-architecture.md §6 |

**App Sandbox is off.** The Xcode template enabled it; it blocked all outbound network,
which is fatal for an app whose whole job is calling provider APIs. Disabling it realizes
the Developer ID decision (docs/app/APP.md: Developer ID precisely *because* the sandbox forbids what the product needs).
Hardened Runtime stays on for notarization. Networking-and-data types are marked
`nonisolated` since the project defaults to MainActor isolation.

## Architecture

The one structural seam the package design accepts (Why below) is real now: **AgentKit**. The app never
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

**Durability mechanics.** `TaskCoordinator` is app code (`Work Agent/Runtime/`, ROADMAP
item 1's conductor move — Recorder has no session-owning API left to export). Each
`TaskCoordinator.start`/`resume` call: records `attemptStarted` in the journal (a
`Recorder` type), runs one full `LanguageModelSession` cycle (Apple resolves any
internal tool round-trips), commits the resulting `TranscriptArchive` and a checkpoint
on success, or — on failure — automatically retries against a designated fallback
executor with the archive replayed through `TranscriptArchive.replay(to:)`, which
strips the failed provider's opaque metadata (FR-006). A `CancellationError` (the app
quitting, or the user hitting Stop) checkpoints the run as `.pausedAwaitingResume`
rather than losing it (FR-072/FR-073).

**Tool tracing** is `InstrumentedTool<Base>` (package-internal to `Recorder`, not
publicly exported): any plain `FoundationModels.Tool` gets durable invocation identity
and a registered/started/completed journal trail just by running through the runtime —
no second tool protocol (runtime-api.md §3). Increment 4 shipped the wrapper and proved
the cycle; **increment 5 ships the first real tools** (`ToolKitFiles`, `ToolKitWeb`,
`ToolKitInteraction`, umbrella'd as `ToolKitForMac`) but does not yet wrap them in
`InstrumentedTool` at the app integration point — the run id `InstrumentedTool` needs
isn't available until `TaskCoordinator` starts the run, so tool calls aren't
individually journaled yet. `ToolKit*` products depend only on `FoundationModels` and
`ToolVocabulary`, never `Recorder` — a consumer can use `ToolKitFiles` with a vendor
model package and no durable runs at all (runtime-api.md §6). `RecorderStore` is
`Recorder`'s only other public surface: a read/append façade over the journal, added
for item 4's cost display to read from — nothing outside the package uses it yet.

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

AgentKit's own suite (`swift test` inside `AgentKit/`) is 67 tests: transcript
round-trips and provider-switch metadata stripping, JSON-Schema→`GenerationSchema`
conversion, `FileRunJournal`/`FileCheckpointStore` durability across a fresh instance
(standing in for a process restart), `InstrumentedTool` journaling, the migrated
Apple-session-semantics suite (cancellation, revert-on-failure, concurrent tool
scheduling, cross-provider transcript reconstruction) built on the reusable
`ScriptedLanguageModel`, and the increment-5 tools: file paging/docx/glob/regex/
read-before-write (`ToolKitFilesTests`, using an in-memory `.docx` fixture built with
ZIPFoundation rather than a committed binary), `fetch_url`'s Markdown rendering and
SSRF host checks against a stubbed `URLSession` (`ToolKitWebTests`), and
`ask_user`/`update_plan` validation against fake presenter/recorder doubles
(`ToolKitInteractionTests`). It builds and passes on both macOS 27 and iOS 27
(`xcodebuild ... -destination 'generic/platform=iOS'`). `TaskCoordinator`
success/failover/resume paths against plain scripted `RunAttemptExecutor` closures
(no network needed to prove durability) moved with the coordinator to the app's own
suite (`Work AgentTests/ConductorTests.swift`).

**Live smoke tests** (`LiveSmokeTests`, app target) hit real provider APIs through
AgentKit's production executors, gated with `.enabled(if:)` on a `TEST_RUNNER_<VAR>` key
so normal runs skip them. No equivalent live test exists for `web_search` — it needs a
Brave Search API key (supplied 2026-07-19; live verification queued, ROADMAP item 3).

**Verification gap, named honestly.** The built app was launched and quit cleanly (no
crash, no fault-level log entry) with the six file tools and `fetch_url` wired into
its live tool list, confirming the app still builds, links, and starts with them
present. The interactive path — send a message, watch a tool actually get called and
its result stream back, quit mid-run, relaunch, see the paused banner, click Resume,
switch conversations mid-stream — was not exercised in the running app; screen-control
access to drive it was declined. This is a real gap between "the mechanics are
unit-tested" and "a human watched it work." (CLAUDE.md now codifies this as a rule,
not a one-off gap: implementing agents never manually test the app via computer-use
or other GUI automation, ever — including for ROADMAP item 1's conductor move, where
`swift test`, `xcodebuild build`/`test` on macOS and iOS, and the demolition greps all
went green, but the send → quit-mid-run → relaunch → resume click-through — the DOD's
own ask — was not run by the implementing agent and needs Toni to run it once.)

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

No tool selection/approval policy, no MCP, no `ask_user`/`update_plan`/`web_search`
app wiring, no `InstrumentedTool` at the app integration point — named in REQUIREMENTS.md
against FR-080/081/083, not silently deferred.

---

## Why it is built this way

The rationale record (absorbed from the former ADRs; app-side rationale — Developer
ID distribution, models.dev registry, SwiftData — moved to docs/app/APP.md).

### Attachments, not an engine (the 2026-07-19 pivot — supersedes the framing below)

The public-API direction changed after Toni's challenge: FM's own transcript
already carries tool calls/outputs for UI rendering, its hooks fire live, and
transcript persistence is a ten-line `Codable` round-trip — so a session-owning
`runtime.run()` entry point trades Apple's documented API for conveniences a
developer can write in an afternoon ("no developer will see the value").
The package therefore attaches to Apple's three sockets (model, tools, profile)
and never wraps the session: Executors, ToolKit, a passive **Recorder** (traces
with timestamps and raw output, budgets+spill, the `read_tool_output` history
tool, replay/evals, the journal-before-execute guard), standalone MCP, Testing,
and small transcript utilities (save/load + the provider-state strip).
`TaskCoordinator`/`RunPolicy`/`SessionAttempt` have moved to app code
(`Work Agent/Runtime/`, ROADMAP item 1) — the package now has no session-owning
public API left to export; its only conductor-adjacent public surface is
`RecorderStore`, a read/append façade over the journal. Design: plans/runtime-api.md.

### Three layers: Foundation Models under a durable runtime under the host

Apple's OS 27 `LanguageModel`/`LanguageModelExecutor`/`LanguageModelSession`/
`Transcript` surface *is* the neutral intelligence-session layer we would otherwise
have built. A bounded POC proved the architecture with live two-request tool cycles
through real Apple sessions for DeepSeek, Google, and Anthropic, plus a live
cross-provider switch. Rejected alternatives: a fully custom loop over our own
message types (duplicates Apple's transcript/schema/session and forks the ecosystem
the package sells to); embedding a TS/Python framework as a subprocess (bundled
runtime in a notarized app, IPC around every Swift tool); a normalization proxy
(flattens provider-specific capability — the opposite of the fidelity promise);
Foundation Models as the *whole* runtime (a Codable transcript is not durable
execution — no checkpoints, restart-safe interrupts, or attempt identity). Honest
caveat, kept on purpose: for the app alone a custom loop would also have served;
Apple's protocol won because this package's market is Foundation Models developers.
The falsifier and retreat path are recorded in ROADMAP's vision preamble.

### Two executors, not eleven

Ten curated providers share the OpenAI-compatible wire format; one executor with
per-provider presets covers them all. Anthropic gets a native Messages executor
because compatibility shims lag exactly the capabilities that matter, and Anthropic
is the single most important provider to get right. We keep our own Anthropic
executor even though Anthropic ships a Foundation Models package: theirs assumes
proxy-backend auth (vs. our local BYOK keys), is beta and closed to contributions,
and failover requires knowing precisely where provider state lives. Known cost we
accepted: we own wire drift (base paths, reasoning field renames, dual endpoints),
and staleness is silent until a provider breaks — the conformance suite is the
drift detector.

### One package, many small products

Swift's unit of encapsulation is the module; the package is the unit of versioning.
Pre-1.0, everything co-evolving against a beta OS shares one package so releases
stay atomic (separate packages would need coordinated releases on every Apple ABI
change — it already broke once between beta seeds). No module is allowed a second
job; the product DAG in plans/runtime-api.md §6 is the contract. ToolKit products
depend only on FoundationModels + ToolVocabulary, never Recorder, so tools work
with any model package and no runtime. A repo/package split happens when release
cadences demonstrably diverge or an external consumer needs a piece standalone —
an event, not a prediction.

### swift-testing with requirement IDs in display names

IDs go in test display names and `// REQ:` comments at the point of satisfaction;
`rg FR-xxx` finds the feature record (PRODUCT.md), the code, and the tests. Chosen
over per-requirement `@Tag`s (a declaration per ID forever, for filtering nobody
has needed) and over a traceability matrix (a third artifact that goes stale first).
No UI tests, permanently: slow, flaky, and they test the wrong layer — coverage is
unit and contract, acceptance is running the thing.
