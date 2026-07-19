# Agent runtime for Apple's Foundation Models

![Swift 6](https://img.shields.io/badge/Swift-6-orange) ![Platforms](https://img.shields.io/badge/platforms-macOS%2027%20%7C%20iOS%2027-blue) ![SPM](https://img.shields.io/badge/SPM-compatible-brightgreen) ![License](https://img.shields.io/badge/license-MIT-lightgrey) ![Status](https://img.shields.io/badge/status-pre--release-yellow)

Swift libraries for building language-model apps on Apple's Foundation Models
framework: cloud provider executors, native tools, durable agent runs, and
deterministic testing — independently importable from one package.

Foundation Models gives every Swift app a session API over any conforming
language model. This package supplies the layers Apple doesn't: getting cloud
providers into that API at full fidelity, giving models native capabilities on
macOS and iOS, making long-running work survive, and making all of it testable.
Each library stands alone, and every dependency is an Apple framework.

## The libraries

| Library | What it gives you | Depends on |
|---|---|---|
| **Executors** | Ten cloud providers as `LanguageModel`s — OpenAI-compatible ×9 and Anthropic native. Provider wire quirks handled, and provider capabilities *beyond* the FM API exposed: typed options for cache control, server-side tools, and thinking budgets; direct clients for non-conversational APIs | FoundationModels |
| **ToolKit** | Ready-made native tools — files (including docx text), web fetch, Contacts, Calendar, Reminders, Mac app control. Each documents the Info.plist keys its host app needs | FoundationModels + the platform framework |
| **RuntimeCore** | Agent runs that survive crash, relaunch, and suspension: append-only journal, checkpoints, resumable interrupts, composable run limits, retry, and cross-provider failover mid-run | FoundationModels |
| **RuntimeTesting** | Scripted models, virtual clocks, and fixture recorders. Agent behavior asserted deterministically, no network. Never links into shipping binaries | FoundationModels |
| **Replay / Evals** | Recorded runs replayed against new models, prompts, or providers | RuntimeCore + RuntimeTesting |
| **MCP** | Model Context Protocol servers as tools, with explicit schema conversion | The one external dependency, opt-in |

Take one library or all of them. ToolKit works with a vendor's model package and
no runtime; RuntimeTesting tests agent code that never imports RuntimeCore.

## Executors

Apple's protocol makes models swappable; someone still has to put each cloud
provider behind it. These executors do, without flattening what makes each
provider different. DeepSeek requires its reasoning content echoed on the
following request; the executor does this. Gemini attaches thought signatures
to tool calls; they round-trip. Anthropic's signed thinking blocks replay
intact. Capabilities the FM API doesn't model — prompt caching, server-side
tools, thinking budgets — are typed options on the executor's configuration,
not lost in translation.

```swift
let claude = AnthropicModel(.sonnet5, apiKey: key,
                            options: .init(serverTools: [.webSearch]))
let deepseek = OpenAICompatibleModel(.deepSeek, apiKey: key)
// Both drop into the same LanguageModelSession slot as Apple's on-device model.
```

## ToolKit

A language model is only as useful as what it can touch. ToolKit ships
`FoundationModels.Tool` conformances for the things Apple-platform apps
actually have: the file system, the web, Contacts, Calendar, Reminders, and —
on macOS — other applications. Tools that need user permission document the
exact usage-description keys the host app must carry. File tools have a plain-
path body on macOS and a security-scoped body on iOS behind the same interface.

```swift
let session = LanguageModelSession(model: claude,
                                   tools: [ReadFile(), SearchContacts()])
// No runtime required — ToolKit works with any Foundation Models provider.
```

## RuntimeCore

`LanguageModelSession` is an in-process conversation; when the process dies,
so does the work. RuntimeCore makes the run — not the process — the unit of
work. Every attempt, tool invocation, and checkpoint is journaled before it
matters. A run resumed after a force-quit continues from its last checkpoint.
A question to the user is a serializable interrupt, so an approval can be
answered after a relaunch. A thrown tool error returns to the model as
corrective output instead of terminating the response. Limits compose: turns,
tokens, cost, wall-clock, tool calls. A run can switch providers mid-flight;
provider-owned state is stripped, the conversation continues.

```swift
let run = try await runtime.run(
    Agent(model: deepseek, instructions: "Prepare the weekly report.",
          tools: [ReadFile(), WriteReport()]),
    policy: .default.maxTurns(30).budget(tokens: 200_000))

for try await event in run.events { render(event) }

// After a crash, a force-quit, or an iOS suspension:
let resumed = try await runtime.resume(run.id)
```

For a quick one-shot answer, `session.respond(to:)` remains exactly what you'd
write without this package. The runtime is the entry point for work that must
survive; it never wraps or replaces Apple's types.

## RuntimeTesting

Agent code is ordinarily untestable: the model is remote, nondeterministic, and
billed. RuntimeTesting makes it a value you script. Assert that your agent
called the right tool with the right arguments, handled a malformed reply,
respected its budget, resumed correctly — in milliseconds, offline, in CI.

```swift
let model = ScriptedModel {
    ToolCallTurn("read_file", ["path": "/tmp/notes.txt"])
    TextTurn("The file says the deadline is Friday.")
}
let run = try await runtime.run(Agent(model: model, tools: [ReadFile.fixture]),
                                clock: VirtualClock())
#expect(run.trajectory.toolCalls.map(\.name) == ["read_file"])
```

The same scripted-model suite doubles as a conformance kit: any
`LanguageModel` package can be certified against the runtime's semantics —
cancellation, retry atomicity, tool-error behavior, state round-trips.

## Replay and evals

Every run's journal is a complete recording. Replay one against a different
model, provider, or prompt and diff the trajectories; keep a directory of
recorded cases as a regression suite that runs offline.

## MCP

MCP servers mount as tools. Foundation Models' `GenerationSchema` accepts a
strict subset of JSON Schema, so conversion is explicit: supported schemas
convert exactly, unsupported keywords are reported with their path and a
documented fallback — never silently flattened. MCP is the only library with a
dependency outside Apple's frameworks, and it's opt-in.

## Requirements

- Xcode 27, Swift 6
- macOS 27 or iOS 27 (the FM provider protocol is OS 27 API)
- Pre-release: APIs track Apple's OS 27 betas, which have already broken ABI
  once between beta seeds. Pin exact versions. No stable tag before OS 27 GA.

Works with any `LanguageModel`: Apple's on-device model, Private Cloud
Compute, [ClaudeForFoundationModels](https://github.com/anthropics/ClaudeForFoundationModels),
Google's Gemini package, or the executors above. Verified to date through real
`LanguageModelSession` tool cycles: DeepSeek, Google, and Anthropic, including
provider-state replay and a live mid-run provider switch (2026-07-18).

## Relationship to Foundation Models

No parallel types. `Transcript`, `Tool`, `@Generable`, and `GenerationSchema`
remain Apple's; code from any Foundation Models tutorial works here unchanged.
The package adds an entry point for durable work and the pieces around it — it
is not a second session API, and it never shadows an Apple noun.

## What this package does not do

Not a model SDK. Not a RAG or memory stack. No graph DSL. No multi-agent
framework. No cloud account, no telemetry, no server. If Apple's framework
does something, this package uses it rather than re-implementing it.

## Apps built on this package

Work Agent for macOS and iOS — native agent apps — are built on these
libraries and serve as their reference implementations.

## Documentation

| Doc | What it answers |
|---|---|
| [RUNTIME.md](docs/product/RUNTIME.md) | The product north star: the layer bet, capabilities, evidence and falsifiers |
| [ROADMAP.md](docs/product/ROADMAP.md) | Increment order and the horizon |
| [REQUIREMENTS.md](docs/product/REQUIREMENTS.md) | What must be true, testably, with permanent IDs |
| [ENGINEERING.md](docs/engineering/ENGINEERING.md) | How the system is built *right now* — reality, never aspiration |
| [Architecture decisions](docs/decisions/) | Why each choice over its alternatives — living ADRs |
| [Research](docs/research/README.md) | What we learned outside this repo, with evidence and dates |
| [Working agreement](CLAUDE.md) | How this repo is run |
| [PRODUCT.md](docs/product/PRODUCT.md) | The Work Agent app (moving to its own repo) |

Design proposals in flight live in [docs/plans/](docs/plans/) — working
documents, binding only once confirmed at an increment's definition-of-ready.

## License

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 Toni Melisma.
