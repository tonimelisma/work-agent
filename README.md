# Agent runtime for Apple's Foundation Models

![Swift 6](https://img.shields.io/badge/Swift-6-orange) ![Platforms](https://img.shields.io/badge/platforms-macOS%2027%20%7C%20iOS%2027-blue) ![SPM](https://img.shields.io/badge/SPM-compatible-brightgreen) ![License](https://img.shields.io/badge/license-MIT-lightgrey) ![Status](https://img.shields.io/badge/status-pre--release-yellow)

Swift libraries for building language-model apps on Apple's Foundation Models
framework: cloud provider executors, native tools, total recall for agent runs,
and deterministic testing — independently importable from one package.

Foundation Models gives every Swift app a session API over any conforming
language model, with three sockets: the model slot, the tools array, and the
session profile. Each of these libraries plugs into a socket — **nothing wraps
or replaces Apple's API**; `session.respond()` stays your only front door, and
code from any Foundation Models tutorial works here unchanged. Each library
stands alone, and every dependency is an Apple framework.

## The libraries

| Library | What it gives you | Depends on |
|---|---|---|
| **Executors** | Ready Foundation Models providers for the popular cloud LLMs that don't ship their own — GPT, DeepSeek, Grok, Kimi, Qwen, and more via one OpenAI-compatible executor, plus Anthropic native. Wire quirks handled; provider capabilities *beyond* the FM API exposed | FoundationModels |
| **ToolKitForMac / ToolKitForiOS** | Ready-made native tools, one import per platform — files (including docx text), web fetch, Contacts, Calendar, Reminders, document creation (PDF, docx, xlsx, pptx). Each tool documents the Info.plist keys its host app needs | FoundationModels + the platform framework |
| **Recorder** | Attach one line and every run is remembered: timestamps, usage, cost, and the *full untruncated* tool output the transcript never keeps. Oversized results reach the model budgeted, with a history tool to page back into the rest. Recordings replay as offline regression suites | FoundationModels |
| **Testing** | Scripted models, virtual clocks, and fixture recorders. Agent behavior asserted deterministically, no network. Never links into shipping binaries | FoundationModels |
| **MCP** | Model Context Protocol servers as plain FM tools for any session — no other library of ours required. Explicit schema conversion, never silent flattening | The one external dependency, opt-in |

Take one library or all of them — none requires another. ToolKit works with a
vendor's model package; the Recorder attaches to any session; Testing tests
agent code that imports nothing else of ours.

## Executors

Apple's protocol makes models swappable, but as of mid-2026 only Anthropic and
Google ship provider packages — there is no Foundation Models package for
OpenAI, DeepSeek, xAI, Moonshot, Alibaba, MiniMax, Meta, or Zhipu. These
executors put them all behind the protocol today: one OpenAI-compatible
executor covers the nine providers that share that wire format, and a native
Anthropic executor covers Claude at full fidelity. None of it flattens what
makes each provider different. DeepSeek requires its reasoning content echoed on the
following request; the executor does this. Gemini attaches thought signatures
to tool calls; they round-trip. Anthropic's signed thinking blocks replay
intact. Capabilities the FM API doesn't model — prompt caching, server-side
tools, thinking budgets — are typed options on the executor's configuration,
not lost in translation.

The commitment is structural, not a feature list: the executor owns the wire,
so a vendor capability never waits for Apple's abstraction to catch up. It
lands in one of three places. Request-level features become typed executor
options. Provider-owned conversation state lives in namespaced transcript
metadata that replays to its owner and is stripped on a provider switch.
Non-conversational surfaces — batch processing, file stores — get plain
direct clients instead of being contorted into a session. Where a provider
accepts richer tool schemas than `GenerationSchema` can express, the executor
can send the fuller schema on the wire and validate host-side. Models are
never cut down to the lowest common denominator to look interchangeable.

```swift
let claude = AnthropicModel(.sonnet5, apiKey: key,
                            options: .init(serverTools: [.webSearch]))
let deepseek = OpenAICompatibleModel(.deepSeek, apiKey: key)
// Both drop into the same LanguageModelSession slot as Apple's on-device model.
```

## ToolKitForMac / ToolKitForiOS

A language model is only as useful as what it can touch. ToolKit ships
`FoundationModels.Tool` conformances for the things Apple-platform apps
actually have: the file system, the web, Contacts, Calendar, Reminders — and
document creation: PDF, docx, xlsx, and pptx produced natively, with no
code-execution sandbox in the loop. For anything else — app control, SaaS
services — mount an MCP server. One import per platform gives you the full
platform-true set; the shared tools present identical schemas on both, so
prompts, evals, and recorded runs transfer between your Mac and iPhone apps.
File tools have a plain-path body on macOS and a security-scoped body on iOS
behind the same interface. Tools that need user permission document the exact
usage-description keys the host app must carry.

```swift
import ToolKitForMac   // or ToolKitForiOS

let session = LanguageModelSession(model: claude,
                                   tools: [ReadFile(), SearchContacts()])
// No runtime required — ToolKit works with any Foundation Models provider.
```

## Recorder

A passive recorder you attach in one line — by wrapping your tools and
installing a session profile. It never touches the session's control flow.

Foundation Models already shows you what happened: the transcript carries every
tool call and tool output, and profile hooks fire live. What it doesn't keep:
anything past the session's lifetime, timestamps, the raw untruncated tool
output (the transcript holds only what the model saw), retries, or tool
failures (a thrown tool error terminates the response and lands nowhere). The
Recorder keeps all of it, locally.

Oversized tool output reaches the model as a first page or summary plus an
instruction for getting more, while the full result lands in the store — and
`recorder.historyTool` lets the model page back into anything it was shown a
summary of (`read_tool_output(invocationID, offset)`). That pairing makes
aggressive context compaction safe: old tool results can be cleared from the
model's window because nothing is ever truly gone. Consequential tools get a
journal-before-execute guard in the same wrapper, so a call that may or may not
have completed before a crash is asked about, never silently repeated. A
recoverable tool error can return to the model as corrective output instead of
killing the response.

```swift
let recorder = Recorder(store: .default)

let session = LanguageModelSession(
    model: OpenAICompatibleModel(.deepSeek, apiKey: key),
    tools: recorder.instrument([ReadFile(), FetchURL(), CreatePDF(),
                                recorder.historyTool]),
    profile: recorder.profile)

try await session.respond(to: prompt)   // Apple's API. Untouched.
```

A recording is also a regression suite: replay it against a different model,
provider, or prompt and diff the trajectories, offline, in CI. Timestamps and
costs feed your dashboards and your debugging — which tool call is slow, what
did this run cost — never the model.

Small utilities ride along, deliberately small: `TranscriptArchive.save/load`
(the transcript is `Codable`; this is the ten-line round-trip, packaged) and
`replay(to:)`, which strips one provider's private conversation state so a
conversation started on DeepSeek can continue on Claude — providers hard-fail
or lose their reasoning thread without this. Retry is a documentation snippet,
not a policy engine.

## Testing

Agent code is ordinarily untestable: the model is remote, nondeterministic, and
billed. Testing makes it a value you script. Assert that your agent
called the right tool with the right arguments, handled a malformed reply,
respected its budget, resumed correctly — in milliseconds, offline, in CI.

```swift
let model = ScriptedModel {
    ToolCallTurn("read_file", ["path": "/tmp/notes.txt"])
    TextTurn("The file says the deadline is Friday.")
}
let session = LanguageModelSession(model: model,
                                   tools: recorder.instrument([ReadFile.fixture]))
try await session.respond(to: "what does the file say?")
#expect(recorder.latest.toolCalls.map(\.name) == ["read_file"])
```

The same scripted-model suite doubles as a conformance kit: any
`LanguageModel` package can be certified against the runtime's semantics —
cancellation, retry atomicity, tool-error behavior, state round-trips.

## MCP

MCP servers mount as plain `FoundationModels.Tool`s that work with any session —
MCP depends on nothing else in this package. `GenerationSchema` accepts a
strict subset of JSON Schema, so conversion is explicit: supported schemas
convert exactly, unsupported keywords are reported with their path and a
documented fallback — never silently flattened. The one external dependency
anywhere, and it's opt-in.

## Requirements

- Xcode 27, Swift 6
- macOS 27 or iOS 27 (the FM provider protocol is OS 27 API)
- Pre-release: APIs track Apple's OS 27 betas, which have already broken ABI
  once between beta seeds. Pin exact versions. No stable tag before OS 27 GA.

Works with any `LanguageModel`: Apple's on-device model, Private Cloud
Compute, [ClaudeForFoundationModels](https://github.com/anthropics/ClaudeForFoundationModels),
Google's Gemini package, or the executors above. Verified to date through real
`LanguageModelSession` tool cycles: DeepSeek, Google, and Anthropic, including
provider-state replay and a live mid-run provider switch (2026-07-18); Alibaba,
xAI, and Apple's own on-device `SystemLanguageModel` also verified live
(2026-07-20). See
[docs/research/provider-chat-endpoints.md](docs/research/provider-chat-endpoints.md)
for the full eleven-provider matrix, passes and failures both.

## Relationship to Foundation Models

No parallel types. `Transcript`, `Tool`, `@Generable`, and `GenerationSchema`
remain Apple's; code from any Foundation Models tutorial works here unchanged.
The package adds no entry point at all — models, tools, and a recorder plug
into the session Apple gave you. It is not a second session API, and it never
shadows an Apple noun.

## What this package does not do

Not a model SDK. Not a RAG or memory stack. No graph DSL. No multi-agent
framework. No cloud account, no telemetry, no server. If Apple's framework
does something, this package uses it rather than re-implementing it.

## Apps built on this package

None yet, in this repo. This repo is SPM-root — a standalone package, no host app
in-tree. A native reference app is a planned, separate effort in its own repo.

## Documentation

| Doc | What it holds |
|---|---|
| [ROADMAP.md](docs/product/ROADMAP.md) | The future: vision and features we intend to build, in priority order |
| [PRODUCT.md](docs/product/PRODUCT.md) | The implemented product: every shipped feature, its ID, and why it's shaped this way |
| [ENGINEERING.md](docs/engineering/ENGINEERING.md) | The implemented architecture and the rationale behind every structural decision |
| [Research](docs/research/README.md) | What we learned outside this repo, with evidence and dates |
| [Working agreement](CLAUDE.md) | The process: research → roadmap → plans → code → product/engineering records → review |

Implementation plans for the top roadmap items live in [docs/plans/](docs/plans/)
and are deleted as they're built.

## License

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 Toni Melisma.
