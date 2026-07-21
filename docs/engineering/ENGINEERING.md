# WorkKit — Engineering

**Status:** Living. Must always describe reality, never aspiration. Last substantive
change: 2026-07-20.

If this doc and the code disagree, the doc is a bug. Fix it in the increment that
caused the drift.

This doc says what is true now AND why it was decided that way -- the rationale for
every structural choice lives in "Why it is built this way" below. There is no
separate decisions log.

---

## Current reality

**This repo is SPM-root: WorkKit is a standalone Swift package, nothing else.**
There is no app in this tree. A Work Agent macOS/iOS app used to live here and
was the package's proving ground; on 2026-07-20 it was deleted outright (not
carved out, not preserved) — "instead of carving the app out, I'll create it
anew... just delete it from this repo, and move the current repo to be an SPM
repo for WorkKit." A future reference app is a separate, later effort in its
own repo, consuming this package as a dependency.

The package gives a host (an app, a CLI, a server — anything with a
`LanguageModelSession`) three things: **Executors** for the clouds Apple ships no
provider for, **ToolKit** native tools, and a **Recorder** that supplies durable-run
primitives (journal, checkpoints, transcript archive with cross-provider replay)
without ever owning the session or the control loop itself. A host builds its own
conductor on top of the Recorder's substrate — this package deliberately ships no
`runtime.run()` entry point (see "Attachments, not an engine" below).

The `Experiments/FoundationModelsPOC/` spike from increments 2–3 is gone: its proven
executors, transcript archive, schema bridge, and session-semantics tests migrated
into this package (see `git log` for its history) rather than living on as a second,
drifting implementation.

```
Package.swift                              name "WorkKit"
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
    RecorderStore.swift                    read/append façade — a host's cost-display API
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
  RecorderTests/                            21 tests: durability, semantics
  ExecutorsTests/                           23 tests: SSE parsing, both wire formats, stream guards,
                                             redacted-thinking round-trip
  ToolKitFilesTests/                        27 tests: paging, docx, glob, read-before-write
  ToolKitWebTests/                          16 tests: Markdown rendering, SSRF, redirects, search
  ToolKitInteractionTests/                  6 tests: ask_user/update_plan validation
docs/                                       specs
```

## Stack

| | | Why |
|---|---|---|
| Language | Swift 6, strict concurrency | Platform-neutral package, not an app |
| Tests | swift-testing | Why below |
| Structure | One SPM package, repo root (`WorkKit`, `Recorder`, `Executors`, `ToolVocabulary`, `RuntimeTesting`, the ToolKit family) | Why below |
| Provider chat/inference | `Executors` — a host builds a `LanguageModelSession` from them directly | Why below |
| Durable-run substrate | `Recorder`: journal + checkpoints + archive replay, attach-only, no owned loop | Why below |
| Min macOS | **27.0** | NFR-009, Why below |
| Package platforms | **iOS 27 and macOS 27**, both build and test green | NFR-010, Why below |
| Tools | `ToolKitFiles`, `ToolKitWeb`, `ToolKitInteraction`, umbrella'd as `ToolKitForMac` | FR-074–083, tool-architecture.md |
| Tool dependencies | ZIPFoundation (.docx is a zip), SwiftSoup (HTML→Markdown) — the only two external dependencies anywhere in the package, both pre-approved pure Swift | Package.swift |

## Architecture

The package never constructs a `URLRequest` to a model provider on a host's behalf —
a host builds a concrete `LanguageModel` (`OpenAICompatibleModel` or `AnthropicModel`)
and hands it, plus tools and instructions, directly to Apple's
`LanguageModelSession`. The package has no import of SwiftUI, AppKit, UIKit, or any
concrete host type (verified: nothing in `Sources/` imports a UI framework or a
host's persistence type) — the dependency direction only ever runs one way, host →
package.

**Durability mechanics.** The Recorder's pieces compose into what a host's own
conductor needs: `RunJournal`/`FileRunJournal` records events (`attemptStarted`,
`attemptCommitted`, `runCompleted`, `runPaused`, `runFailedOver`, ...);
`CheckpointStore`/`FileCheckpointStore` persists the position to resume from;
`TranscriptArchive` wraps Apple's `Transcript` with a version and a `replay(to:)`
that strips a departing provider's opaque metadata so a session can continue on a
different provider. None of this runs a loop or constructs a session — a host reads
and writes these types around its own orchestration. `FileRunJournal.events(for:)`
tolerates a **torn tail**: a crash mid-append leaves a partial final line, and since
that's the expected residue of the exact failure the journal exists to survive,
everything decoded before it is still returned rather than the whole read throwing;
corruption anywhere else in the file still throws `corruptEntry`, since that's a
real integrity problem, not crash residue. `InstrumentedTool`'s `toolRegistered`
journal write propagates its failure instead of swallowing it with `try?` — the
registered-before-execute guarantee means a tool must never run unrecorded; the
later `toolStarted`/`toolCompleted` writes stay best-effort on purpose, since a
post-effect write failure must not destroy an already-successful result.

**Tool tracing** is `InstrumentedTool<Base>` (package-internal, not publicly
exported — the public wrapper API waits for a real external consumer): any plain
`FoundationModels.Tool` gets durable invocation identity and a
registered/started/completed journal trail just by running through it — no second
tool protocol. `ToolKit*` products depend only on
`FoundationModels` and `ToolVocabulary`, never `Recorder` — a consumer can use
`ToolKitFiles` with a vendor model package and no durable runs at all.
`RecorderStore` is `Recorder`'s only other public surface: a
read/append façade over the journal, for a host's own cost-display or history UI to
read from — nothing in this repo uses it yet, since nothing in this repo is a host.

**`fetch_url`'s redirects are walked manually, never by URLSession.** A
`URLSessionTaskDelegate` blocks automatic redirect-following
(`willPerformHTTPRedirectionResponse` returns `nil`), so a 3xx response's `Location`
is inspected and re-validated by `NetworkSafety.assertPublicHost` on every hop
before any request reaches it, capped at 5 hops. This replaces a real gap: with
automatic following, the SSRF check only ever saw the *original* host, so a public
URL that redirected to an internal address was fetched before the post-hoc
cross-host check could reject it. The response body is also capped while
streaming (`URLSession.AsyncBytes`, byte-by-byte), never after buffering the full
response. Accepted, not fixed: DNS-rebinding TOCTOU — the host is resolved and
checked once, then `URLSession` resolves it again to actually connect; closing
that gap needs a custom connection layer this tool doesn't have.

## Testing

`swift-testing`, unit and contract. **No UI-test target, now or later.** This
package ships no UI; UI automation is a host's concern, never this package's.

Requirement IDs go in test display names:

```swift
@Test("FR-080: ask_user validates shape and defers to the host-injected presenter")
func askUserValidatesQuestionCount() async throws { ... }
```

`rg "FR-080"` finds the requirement, the code, and the test. That's the whole scheme —
see [CLAUDE.md](../../CLAUDE.md) § Traceability for why there are no per-requirement
tags.

The package's own suite (`swift test` from the repo root) is 94 tests: transcript
round-trips and provider-switch metadata stripping, JSON-Schema→`GenerationSchema`
conversion, `FileRunJournal`/`FileCheckpointStore` durability across a fresh instance
(standing in for a process restart) including torn-tail and corrupt-checkpoint
tolerance, `InstrumentedTool` journaling including its registration-failure
propagation, the migrated Apple-session-semantics suite (cancellation,
revert-on-failure, concurrent tool scheduling, cross-provider transcript
reconstruction) built on the reusable `ScriptedLanguageModel`, the increment-5
tools: file paging/docx/glob/regex/read-before-write (`ToolKitFilesTests`, using
an in-memory `.docx` fixture built with ZIPFoundation rather than a committed
binary), `fetch_url`'s Markdown rendering, redirect-walking, streaming-cap, and
SSRF host checks against a stubbed `URLSession` (`ToolKitWebTests`), the executor
stream guards (non-SSE Content-Type, zero-event streams, error-body capture),
Anthropic's reasoning-level→effort mapping against a stubbed `URLSession`, and
its `redacted_thinking` round-trip (parser, bridge accumulation, encoder
ordering) (`ExecutorsTests`), and `ask_user`/`update_plan` validation against fake
presenter/recorder doubles (`ToolKitInteractionTests`). It builds and passes on
both macOS 27 and iOS 27
(`xcodebuild -scheme WorkKit-Package -destination 'generic/platform=iOS' build`).

**Gap, named honestly.** Gated live-provider smoke tests (`LiveSmokeTests`,
`TEST_RUNNER_<VAR>`-gated, hitting real provider APIs through this package's
production executors) previously lived in the Work Agent app's test target and did
not migrate — they tested the app's integration of the executors, not standalone
package API. This package currently has **no live-provider verification of its
own**; building that gated infrastructure directly in this package's `Tests/` is
ROADMAP item 1. `TaskCoordinator`'s success/failover/resume test suite
(`ConductorTests`) is gone the same way — it tested app-owned orchestration code
that no longer exists in any repo this project controls.

Tests are necessary and not sufficient. A green suite over a feature nobody
exercises live is how agents convince themselves of things that aren't true — named
here rather than silently dropped.

## Conventions

- Requirement references at the point of satisfaction: `// REQ: FR-001 — <what and why>`.
  On the code that satisfies it, not on the file.
- Comments state constraints the code can't. Not what the next line does.
- No implementation vocabulary in a tool's model-facing output.

## Deferred, and why it's not here

No CI, no linter, no logging framework, no error taxonomy. Each is a real need, and
each is a decision better made with code to point at. They land in the increment that
needs them.

No tool selection/approval policy, no MCP, no `ask_user`/`update_plan`/`web_search`
wiring to any host — there is no host in this repo to wire them to. Named against
FR-080/081/083, not silently deferred.

---

## Why it is built this way

The rationale record (absorbed from the former ADRs).

### Attachments, not an engine (the 2026-07-19 pivot)

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
`TaskCoordinator`/`RunPolicy`/`SessionAttempt` — the concrete orchestrator that
used to sit above the Recorder — moved to the Work Agent app in ROADMAP item 1's
first pass (2026-07-20), then left this project entirely when the app itself was
deleted the same day. The package now has no session-owning public API and never
will; its only conductor-adjacent public surface is `RecorderStore`, a read/append
façade over the journal.

### Three layers: Foundation Models under a durable runtime under a host

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
caveat, kept on purpose: for a single app alone a custom loop would also have
served; Apple's protocol won because this package's market is Foundation Models
developers. The falsifier and retreat path are recorded in ROADMAP's vision
preamble.

### Typed tools, not a shell/patch executor

Two proven tool-design philosophies exist: Codex's single PTY executor plus a
patch format (safety from an OS sandbox), and Claude Code's many typed tools
(safety from per-tool permissions). This package took the typed-tool style, for
reasons specific to us, not a general verdict: our eleven vendors' models share
no `exec_command`/`apply_patch` RL training the way Codex's model does, but all
of them have seen read/write/search-shaped tools, so conventionally-named typed
tools are the lowest-variance interface across vendors and keep per-provider
schema quirks confined to the adapters. A typed `read_file(path:)` also renders
as "Read Q3 report.docx" for free in any UI, where an opaque shell string needs
a command-parsing layer non-developers wouldn't trust anyway. Users' work lives
in documents and folders, not terminals, so a shell tool's isolation story
(needed before it could ship safely) stays deferred rather than built. Taken
from Codex anyway: token-denominated output budgets with paging/truncation, and
the effect/idempotency taxonomy tools carry as `ToolAnnotations` data.

### Two executors, not eleven

Ten curated providers share the OpenAI-compatible wire format; one executor with
per-provider presets covers them all. Anthropic gets a native Messages executor
because compatibility shims lag exactly the capabilities that matter, and Anthropic
is the single most important provider to get right. We keep our own Anthropic
executor even though Anthropic ships a Foundation Models package: theirs assumes
proxy-backend auth (vs. local BYOK keys), is beta and closed to contributions, and
failover requires knowing precisely where provider state lives. Known cost we
accepted: we own wire drift (base paths, reasoning field renames, dual endpoints),
and staleness is silent until a provider breaks — the conformance suite is the
drift detector. Anthropic's `redacted_thinking` blocks round-trip the same way
signed thinking blocks do: carried as reasoning-entry metadata (an opaque array,
JSON-encoded, since a response can carry several), stripped by the existing
provider-prefix filter on a cross-provider replay with no archive changes.

### One package, many small products

Swift's unit of encapsulation is the module; the package is the unit of versioning.
Pre-1.0, everything co-evolving against a beta OS shares one package so releases
stay atomic (separate packages would need coordinated releases on every Apple ABI
change — it already broke once between beta seeds). No module is allowed a second
job; the file tree above and `Package.swift`'s target graph are the contract. ToolKit products
depend only on FoundationModels + ToolVocabulary, never Recorder, so tools work
with any model package and no runtime. A repo/package split happens when release
cadences demonstrably diverge or an external consumer needs a piece standalone —
an event, not a prediction.

### SPM-root, no app in this repo

The repo carried a Work Agent macOS/iOS app alongside the package from the start,
as the package's proving ground and only consumer. On 2026-07-20 Toni decided
against carrying that app forward (carve-out or otherwise): "instead of carving
the app out, I'll create it anew... don't worry about the app. just delete it from
this repo." The app's FR-numbered product features (chat UI, provider settings,
conversation persistence) are deleted from this project's traceability, not moved
— a future app rebuilding similar features in its own repo mints its own IDs there.
What survives here is only what was genuinely package-level: the Recorder's
durable-run substrate, the Executors, and ToolKit. This is a stronger boundary
than the carve-out plan would have produced (which still implied a coordinated
two-repo release relationship); deleting outright makes this package's public
surface the only thing that has to hold together.

### swift-testing with requirement IDs in display names

IDs go in test display names and `// REQ:` comments at the point of satisfaction;
`rg FR-xxx` finds the feature record (PRODUCT.md), the code, and the tests. Chosen
over per-requirement `@Tag`s (a declaration per ID forever, for filtering nobody
has needed) and over a traceability matrix (a third artifact that goes stale first).
No UI tests, permanently: this package ships no UI.
