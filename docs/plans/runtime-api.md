# Plan: the package's developer-facing API — future state

**Status: north star, rewritten 2026-07-19 after the attachment pivot.** Toni's
verdicts that forced it, verbatim: "bypassing the core FM API so I can get a few
convenience functions is horrible. we should definitely not do that. no developer
will see the value." · "switching providers is not enough for doing the RuntimeCore
for now. if that's the real value, it's not much." · "MCP support should live
somewhere else, it shouldn't depend on using our runtime should it?" · earlier:
"the bigger value prop is the ready tools etc. the durability is not a key issue."
Binding details are still confirmed per increment; this doc is the end state.
**The attachment refactor that gets the tree to this end state shipped
2026-07-20** (session-owning API left the package entirely, then the app itself
was deleted from this repo the same day — see PRODUCT.md/ENGINEERING.md); the
public attachment-API polish described in §3 remains parked in the riffraff for
the first external consumer. This doc remains the end state for what's still
unbuilt.
Supported models explicitly include Apple's built-in `SystemLanguageModel` and
Private Cloud Compute ("Apple Foundation Models support is cheap since it's
built-in so we'll do that"); third-party local models are never built.

---

## 1. The rule: attach, never replace

Foundation Models has three sockets: the `model:` slot, the `tools:` array, and
the session profile/hooks. **Every product plugs into a socket. Nothing owns or
wraps the session; `session.respond()` is the only front door; there is no
`runtime.run()`.** A developer's bare-FM code stays valid line for line, and every
capability is evaluable in one added line.

What FM already provides (verified against the OS 27 SDK — do not rebuild):
the `Transcript` contains typed entries for every tool call and tool output, so
UI rendering of "what happened" needs no library; dynamic-profile hooks
(`onPrompt`/`onResponse`/`onToolCall`) fire live; usage events exist. What FM
does **not** provide — the Recorder's exact scope: persistence across time,
timestamps/durations, the raw untruncated tool output (the transcript holds only
what the model saw), attempt/retry structure, tool *failures* (a thrown tool
error terminates `respond()` and lands nowhere), and cross-run organization.

## 2. The canonical example

```swift
import FoundationModels
import Executors, ToolKitForMac, Recorder      // + MCP if wanted

let recorder = Recorder(store: .default)

let session = LanguageModelSession(
    model: OpenAICompatibleModel(.deepSeek, apiKey: key),      // socket 1
    tools: recorder.instrument(                                 // opt-in wrapping
        [ReadFile(), FetchURL(), CreatePDF()]                   // socket 2
        + mailServer.tools                                      // MCP — plain FM tools
        + [recorder.historyTool]),                              // read_tool_output
    profile: recorder.profile)                                  // socket 3

try await session.respond(to: prompt)          // Apple's API. Untouched.
```

## 3. The products

### Executors — socket 1 (unchanged by the pivot)

Ready FM providers for the clouds that ship none (OpenAI-compatible ×9, Anthropic
native), full provider fidelity via the three-tier extension design: (1) typed
executor options for request-level features — with the **neutral-API rule**: a
capability several providers share (prompt caching, hosted search, thinking
budgets, compaction) gets one provider-neutral API mapped per executor; only true
exclusives get provider-specific options; (2) provider-owned conversation state
in namespaced, ownership-tagged transcript metadata (DeepSeek reasoning echo,
Gemini thought signatures, Anthropic signed thinking — live-verified); (3) plain
direct clients for non-conversational APIs (batches, file stores). The wire
belongs to the executor: fuller tool schemas than `GenerationSchema` expresses
may be sent and validated host-side.

### ToolKit — socket 2 (unchanged; the headline value)

Plain `FoundationModels.Tool` conformances, platform umbrellas (`ToolKitForMac`
/ `ToolKitForiOS`) over shared domain targets that own the schemas: Files, Web,
Interaction, Documents (PDF/docx/xlsx/pptx creation — native OOXML/PDFKit, no
code-execution sandbox), PIM. Effects/idempotency travel as `ToolAnnotations`
data (policy table → `.annotations(...)` modifier → optional refinement
conformance → MCP hints → conservative default) — never a second tool protocol.
No app-control target, ever ("There's MCPs for that").

### Recorder — sockets 2+3, the pivot's centerpiece

A passive recorder, attached by wrapping tools and installing profile hooks.
Nothing about it touches the session's control flow.

- **Capture**: per tool call — invocation ID, timestamps/duration, arguments,
  **full untruncated output** (the model-facing result may be budgeted; the
  store keeps everything); per turn — prompts, responses, usage/cost; failures
  included (the wrapper sees what the transcript never records).
- **Budgets + spill**: oversized tool output reaches the model as a first page
  or summary *plus a recovery instruction*; the full output is already in the
  store. The proven pattern (Claude Code persists >50KB outputs to files the
  model then reads; verified first-hand in our research).
- **The history tool**: `read_tool_output(invocationID, offset)` — the model
  pages back into anything it was shown a summary of. Grounded twice over:
  Claude Code's spill-file reads, and Anthropic's context editing whose
  documented recovery is *re-running* tools — recall from the store is free and
  side-effect-safe where re-running is not.
- **Compaction, made safe by recall**: clearing/summarize strategies (and
  provider-native compaction via executor options) can be aggressive precisely
  because nothing is ever truly gone — the clearing+recall *pair* is the unit no
  framework ships.
- **Consequential-tool guard**: journal-before-execute inside the same wrapper —
  registered-without-outcome on relaunch means "may have happened; ask, don't
  re-run." Kept because the wrapper is already there and email (roadmap) is what
  makes it earn rent; it is *not* marketed as durability.
- **Corrective tool errors** (wrapper option): a recoverable thrown error
  returns to the model as structured output instead of terminating `respond()`.
- **Replay + evals**: the store's recordings replayed against another
  model/prompt with trajectory diffing; recorded-case regression suites offline
  in CI. Timestamps serve the developer (latency/cost views — the LangSmith
  P50/P99 use), never the model.

### MCP — standalone, by decree

Depends on FM + the schema bridge + the swift-sdk (behind a package trait) —
**never on the Recorder or anything else of ours**. Its tools are plain FM tools
usable with a bare session. Schema conversion is explicit: exact-subset
conversion or a precise rejection with keyword and path; the degradation ladder
governs the rest.

### Testing (unchanged)

`ScriptedLanguageModel`, virtual clocks, fixture recorders — public API, never
linked into shipping binaries. Doubles as the conformance kit for third-party
model packages.

### Utilities — demoted, deliberately small

`TranscriptArchive.save/load` (the 10-line Codable round-trip, packaged) and
`replay(to:)` (the provider-state strip that makes mid-conversation model
switching work — real, but "not enough" to justify an engine, so it ships as a
free function). Retry is a documentation snippet, not a policy engine.

## 4. What died, with the reasons on the record

- **`runtime.run()` / any session-owning entry point** — "no developer will see
  the value"; FM's own API is the product surface we attach to.
- **`TaskCoordinator` as public API** — becomes reference-app code: *our*
  conductor, shown in the app, not imposed by the package.
- **`RunPolicy` as a framework concept**; composable limit machinery parked.
- **Restart-surviving interrupts, side-effect *enforcement* machinery** — parked
  until real use proves them ("I actually feel like the functionality and plans
  here got ahead of where I wanted to go").
- Durability as positioning — the guard survives as a Recorder feature; the
  word stops leading anything.

## 5. DX commitments

Attach, don't adopt — one line per capability, verifiable in thirty seconds.
Strict Swift 6; no SwiftUI imports; no second transcript type, no `Generable`
wrappers, no simple-mode fork, no cloud account, no telemetry. Test doubles are
first-class. Macros only where they delete real boilerplate.

## 6. Package structure — one package, small products

```text
                    FoundationModels (Apple, OS 27)
          ▲              ▲                ▲            ▲          ▲
     Executors     ToolVocabulary     Recorder      Testing   TranscriptUtilities
     (no deps of   (annotation/       (store, tool  (doubles) (save/load/strip)
      ours)         budget values)     wrapper,
                         ▲             hooks, history
              ┌────┬─────┼──────┬──┐   tool, replay/evals)
        ToolKitFiles Web Docs  PIM │        ▲
              ▲      ▲    ▲     ▲  │        │ (Replay reads the store;
              └──┬───┴────┴─────┘  │        │  Evals also uses Testing)
        ToolKitForMac / ToolKitForiOS (umbrellas apps import)

        SchemaBridge (FM only) ◀── MCP ──▶ modelcontextprotocol/swift-sdk
                                   (trait-gated; the only external dep;
                                    depends on nothing else of ours)
```

Rules: module = one job; ToolKit and MCP never import Recorder; Recorder never
touches session control flow; a target that grows a second job is a bug. The
former RuntimeCore internals (identifiers, journal, checkpoint store, archive)
live on *inside* Recorder and TranscriptUtilities — the code survives; the
public engine around it does not.
