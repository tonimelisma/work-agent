# Plan: ROADMAP item 1 — the attachment refactor + demolition

**Status: ready to implement, verified against the tree 2026-07-20.** Written for
an implementing agent needing no product judgment. Goal per ROADMAP item 1: the
conductor moves into the app, the journal becomes the Recorder's store with a read
API, the demolition list is executed, and the DOD greps prove it. Code increment:
worktree + PR.

## Verified current state (do not re-derive; re-verify only if the tree moved)

- `AgentKit/Package.swift`: products `ToolVocabulary`, `RuntimeCore`, `Executors`,
  `RuntimeTesting`, `ToolKitFiles/Web/Interaction/ForMac`. `RuntimeCore` target
  depends only on `ToolVocabulary`.
- `AgentKit/Sources/RuntimeCore/` contains exactly: `Identifiers.swift`,
  `RunEvent.swift`, `TranscriptArchive.swift`, `SchemaBridge.swift`,
  `RunPolicy.swift`, `RunJournal.swift`, `CheckpointStore.swift`,
  `RunStatus.swift`, `InstrumentedTool.swift`, `SessionAttempt.swift`,
  `TaskCoordinator.swift`.
- `TaskCoordinator` is FM-free (attempt executor injected as a closure typed
  `RunAttemptExecutor`); `SessionAttempt.swift` holds `runSessionAttempt` (the
  only place a `LanguageModelSession` is built) and `RunAttemptResult`.
- The app's only package touchpoints for the engine: `Work
  Agent/Chat/RuntimeEnvironment.swift` (`import RuntimeCore`, constructs
  `TaskCoordinator`, calls `runSessionAttempt`) and `ChatViewModel.swift`.
- **Usage is already journaled**: `RunEvent.attemptCommitted(RunID, AttemptID,
  inputTokens:, outputTokens:)`. Cost display (item 4) needs only a *read* API
  plus app-side pricing — no new capture is required for tokens. (Per-model
  pricing lives in the app's models.dev registry data, not the package.)
- Tests: `RuntimeCoreTests` (20) covers coordinator/journal/archive/semantics;
  app target has 45 unit + 5 live-smoke.

## Step 1 — rename the module: `RuntimeCore` → `Recorder`

- `git mv AgentKit/Sources/RuntimeCore AgentKit/Sources/Recorder`; same for
  `Tests/RuntimeCoreTests` → `Tests/RecorderTests`.
- Package.swift: rename target and product `RuntimeCore` → `Recorder` (keep the
  `ToolVocabulary` dependency); rename the test target and its dependency.
- Fix every `import RuntimeCore` (package tests + the two app files) to
  `import Recorder`.

## Step 2 — move the conductor into the app

- `git mv` out of the package into a new app group `Work Agent/Runtime/`:
  `TaskCoordinator.swift`, `RunPolicy.swift`, `SessionAttempt.swift`.
- They compile in the app unchanged except: their `public` declarations become
  `internal` (default — delete the `public` keywords; the app is their only
  consumer now), and they gain `import Recorder` for the types that stay in the
  package (`RunID`, `RunEvent`, `RunJournal`, `CheckpointStore`,
  `TranscriptArchive`, `RunStatus`, `RunAttemptResult` moves with
  SessionAttempt).
- Move their tests: extract the coordinator/policy test cases from
  `RecorderTests` into the app test target (`Work AgentTests/ConductorTests.swift`);
  they run against the app module now. Journal/archive/schema/semantics tests
  stay in `RecorderTests`.

## Step 3 — the Recorder's public surface (minimal, deliberate)

- `InstrumentedTool.swift`: change `public` → `internal`. (The public wrapper
  API is riffraff; nothing outside the package uses it today — verify with
  `rg InstrumentedTool "Work Agent"` before and after.)
- Add one small type, `RecorderStore` (new file `RecorderStore.swift`): a
  read/append façade over `FileRunJournal` — `append(_ event: RunEvent)`,
  `events(forRun: RunID) -> [RunEvent]`, `allRuns() -> [RunID]`. This is the
  API item 4's cost display reads. No other new public API.
- `SchemaBridge`, `TranscriptArchive`, `CheckpointStore`, `RunStatus`,
  `Identifiers`, `RunEvent`, `RunJournal` stay in `Recorder`, public, unchanged.

## Step 4 — demolition greps (the DOD proves deletion)

All must return zero in `AgentKit/`:

```
rg "TaskCoordinator|RunPolicy|runSessionAttempt|RunAttemptExecutor" AgentKit/
rg "RuntimeCore" AgentKit/ "Work Agent" "Work AgentTests" docs README.md
rg "public struct InstrumentedTool|public.*InstrumentedTool" AgentKit/
```

Plus: no product or target named `RuntimeCore`; `swift package dump-package`
lists no session-owning API product.

## Step 5 — verify

- `swift test --package-path AgentKit` green on macOS; the iOS destination build
  (`xcodebuild -destination 'generic/platform=iOS'`) green.
- App: build, launch, send a message on a live provider, quit mid-run, relaunch,
  resume — the conductor now being app code must change nothing observable.
- App unit tests green (45 + moved conductor tests).

## Step 6 — docs, same PR

- ENGINEERING.md: tree listing (Recorder module, app `Runtime/` group), stack
  table rows, "Attachments, not an engine" note updated from "slated" to done.
- PRODUCT.md: run-mechanics pivot note updated (migration executed); product
  list in the intro (`RuntimeCore` → `Recorder`).
- README: no changes needed (already post-pivot) — verify with the greps.
- ROADMAP: delete item 1; renumber.
- Delete this plan (absorption rule).

## Out of scope (do not do)

Recorder capture features (profile hooks, budgets, history tool), any
`recorder.instrument` public API, corrective errors, cost *display* (item 4,
app UI), GLM auth, tool wiring — all later items or riffraff. If a step here
conflicts with the tree, stop and say so; do not improvise.
