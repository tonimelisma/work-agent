# WorkKit — The Product That Exists

**Implemented features only.** Future work lives in [ROADMAP.md](ROADMAP.md); how the
code works lives in [ENGINEERING.md](../engineering/ENGINEERING.md). Every feature
here carries its permanent ID and the reason it's shaped the way it is, quoting Toni
where he decided. IDs are never reused or renumbered; dropped IDs are deleted.
**Next free: FR-084 · NFR-011.**

WorkKit today: a local Swift package on Foundation Models (macOS 27 + iOS 27) with
products `Recorder`, `Executors`, `ToolVocabulary`, `RuntimeTesting`, and the
ToolKit family (`ToolKitFiles`, `ToolKitWeb`, `ToolKitInteraction`, umbrella
`ToolKitForMac`). 67 package tests, green on both platforms. MIT. This repo is
SPM-root — there is no app in this tree; a native reference app is a separate,
later effort in its own repo (2026-07-20: "just delete it from this repo, and
move the current repo to be an SPM repo for WorkKit").

---

## Provider neutrality through Apple's protocol

- **FR-001 — Implemented.** All inference goes through a provider abstraction; no
  feature depends on a specific vendor. *Why this shape:* "we need to be able to
  innovate as an app irrespective of the LLMs." The abstraction is Apple's own
  `LanguageModel`/`LanguageModelExecutor` protocol rather than a bespoke one,
  because the Swift ecosystem is standardizing on it (vendor packages, community
  clones) and a parallel type system would fork that ecosystem. The honest caveat
  recorded with the decision: for a single app alone a custom loop would also have
  served; Apple's protocol won because the *package's* market is Foundation Models
  developers. If that bet dies, this choice has a falsifier and revisiting is kept
  cheap (executors are ours, the loop strategy is swappable).
- **NFR-009 — Implemented.** macOS 27 minimum (the provider protocol is OS 27 API).
- **NFR-010 — Implemented.** The package builds and its suite passes on iOS 27 and
  macOS 27 both.
- **The FR-001 / FR-060 tension is the design, on purpose.** FR-001 says the
  *package* never depends on one vendor; FR-060 (roadmap) says a *model* is never
  dumbed down to the common denominator. Both hold: any provider works, and each
  provider lights up everything it can do. What we never do is delete a capability
  because a competitor lacks it.

## Executors: ten cloud providers behind the protocol

- **Implemented** (built with FR-001): one OpenAI-compatible executor covers the
  nine curated providers sharing that wire format; one Anthropic executor speaks
  Messages natively. *Why two, not eleven:* ten providers share one de facto wire
  standard, so eleven bespoke clients would be waste; Anthropic gets native
  treatment because a compatibility shim would lag the capabilities that matter.
  *Why ours even where vendor packages exist:* Anthropic's package assumes
  proxy-backend auth (opposed to local BYOK keys), is beta and closed to
  contributions, and cross-provider failover requires knowing exactly where
  provider state lives.
- Provider-owned conversation state round-trips at full fidelity — DeepSeek's
  mandatory `reasoning_content` echo, Gemini thought signatures, Anthropic signed
  thinking blocks — verified live against real endpoints. *Why it matters:* these
  requirements are invisible until the second request of an agent loop, and
  "we're not trying to neuter them" (FR-060's principle; full fidelity work
  continues on the roadmap).

## The Recorder: durable-run substrate, attach-only

**The attachment pivot, recorded:** after pressure-testing durability's value
("can you really explain the value of durability here?… It's more your hobby
horse than mine"; "bypassing the core FM API… is horrible"), the public-API
direction changed — see plans/runtime-api.md. The Recorder never owns a session
or a control loop; it gives a host the durable primitives to build one.

- **Implemented.** An append-only run journal (`RunJournal`/`FileRunJournal`,
  fsync'd jsonl), an atomic checkpoint store (`CheckpointStore`/`FileCheckpointStore`),
  a versioned `TranscriptArchive` with `replay(to:)` (strips a departing provider's
  opaque metadata so a conversation can continue on a different provider), and
  `RecorderStore`, a minimal read/append façade over the journal for a host's own
  cost-display or history UI. None of these constructs a `LanguageModelSession` or
  runs a loop — a host (an app, a CLI, a server) owns that and calls into the
  Recorder for durability.
- Tool instrumentation without a second tool type: any plain `FoundationModels.Tool`
  gains durable invocation identity and a journal trail through
  `InstrumentedTool<Base>` (package-internal — the public wrapper API waits for a
  real external consumer). *Why no WorkKit tool protocol:* Apple's `Tool` has no
  metadata slot but sessions take existentials, so wrapping beats forking the
  ecosystem's tool noun — effects and idempotency travel as `ToolAnnotations` data.

**Dropped, honestly:** FR-006 (automatic cross-provider failover), FR-072, and
FR-073 (pause-on-quit / resume-on-relaunch) were previously recorded here as
implemented — they described the full behavior of `TaskCoordinator`, an
orchestrator that lived in the (now-deleted) Work Agent app, not in this package.
The substrate it was built on (journal, checkpoint store, archive replay) remains
and is documented above; the orchestration loop that made those specific EARS
statements true does not exist in this repo. Per the ID discipline, dropped IDs
are deleted outright rather than left claiming something no longer built here.

## ToolKit: native tools as package products

*Why in the package at all:* "one of the most valuable parts of this SPM" and
"absolutely not in the app" (Toni, 2026-07-18). Tools depend only on
`FoundationModels` + `ToolVocabulary`, never `Recorder` — usable with any model
package, runtime optional.

- **FR-074–079 — Implemented.** The six file tools (`read_file`, `list_folder`,
  `find_files`, `search_files`, `write_file`, `edit_file`): plain paths ("We don't
  have folders. Permissions come later"), 2,000-line/2,000-char paging with
  model-followable truncation notices, docx text extraction (a .docx is a zip),
  read-before-write/edit ledgers, native Swift regex search — no bundled binaries
  ("I generally prefer native Swift").
- **FR-082 — Implemented.** `fetch_url`: HTML→Markdown, paged, SSRF-guarded
  (private/link-local/metadata hosts denied post-resolution). *Why paged markdown,
  no extraction model:* Toni chose it — zero per-fetch model cost.
- **FR-083 — Implemented, not live-verified.** `web_search`, Brave-backed ("Both"
  — provider-hosted search plus a neutral backend was Toni's call; Brave chosen as
  the conventional-SERP fallback). Tested against stubbed responses; the Brave key
  arrived 2026-07-19 — live verification is ROADMAP item 1.
- **FR-080 / FR-081 — Implemented in package, not yet surfaced.** `ask_user` and
  `update_plan`, validated against presenter/recorder doubles; no host currently
  wires them to a UI.
- Umbrella product `ToolKitForMac` re-exports the platform-true set. *Why umbrellas
  over platform silos:* one import per platform for developers, shared domain
  targets underneath because the overlap (parsers, paging, schemas) is the
  expensive part and schemas must stay identical cross-platform (Toni: two
  platform toolkits, 2026-07-19).

## Deterministic testing

- **Implemented.** `RuntimeTesting` ships `ScriptedLanguageModel` — agent behavior
  asserted offline, deterministically, in CI; the migrated Apple-session-semantics
  suite (cancellation, revert-on-failure, concurrent tools, cross-provider
  reconstruction) runs on it. *Why first-class:* agent code is ordinarily
  untestable, and test doubles as public API is the package's sharpest DX bet.

## Implemented requirements — verbatim, numbered, traced

The testable statements, exactly as minted (NFR-005: every requirement traceable to
code and tests by ID — `rg <ID>` finds all three). Trace column verified 2026-07-20
by grep; a ✗ is an honest gap, not an oversight.

| ID | Statement | Code | Tests |
|---|---|:-:|:-:|
| FR-001 | The system shall perform all model inference through a provider abstraction, such that no feature depends on a specific model vendor. | ✓ | ✗ — no test carries the ID; the increment-6 cold-provider test is its proof |
| FR-074 | The system shall provide a `read_file` tool that reads text, image, PDF, and docx content from a path, paging output that exceeds the model-facing budget. | ✓ | ✓ |
| FR-075 | The system shall provide a `list_folder` tool that lists a directory's entries, optionally recursive to a bounded depth. | ✓ | ✓ |
| FR-076 | The system shall provide a `find_files` tool that matches file paths by glob pattern under a root. | ✓ | ✓ |
| FR-077 | The system shall provide a `search_files` tool that greps file contents by regex, implemented in native Swift with no bundled binary. | ✓ | ✓ |
| FR-078 | The system shall provide a `write_file` tool that creates or atomically replaces a file's contents. | ✓ | ✓ |
| FR-079 | The system shall provide an `edit_file` tool that performs an exact-match string replacement, requiring the file to have been read first. | ✓ | ✓ |
| FR-080 | The system shall provide an `ask_user` tool that suspends the run to ask the user 1–4 questions with 2–4 options each plus free text, resuming on answer. | ✓ | ✓ |
| FR-081 | The system shall provide an `update_plan` tool that records an ordered list of steps with exactly one in progress. | ✓ | ✓ |
| FR-082 | The system shall provide a `fetch_url` tool that fetches a web page and returns it as paged Markdown, with no extraction model call. | ✓ | ✓ |
| FR-083 | The system shall provide a `web_search` tool: the provider's hosted search where the provider offers one, else a neutral Brave-backed search. | ✓ | ✓ stubbed — never live |
| NFR-005 | Every requirement shall be traceable to code and tests by its ID. | this table | — |
| NFR-010 | The native Swift agent-runtime SPM package shall support iOS 27 and macOS 27 and accept any model conforming to Foundation Models `LanguageModel`, whether its executor uses a cloud API or on-device inference. | ✓ | ✗ — proven by the dual-platform CI build, no single test names it |

## Known gaps, named

Recorded honestly rather than silently skipped: no gated on-device
`SystemLanguageModel` test yet (no eligible-device cycle); `web_search` never ran
live (key now supplied; verification queued); no host in this repo wires
`InstrumentedTool`, `ask_user`, or `update_plan` to anything — that's a consuming
app's job, and no such app lives here anymore. Each is a roadmap item, not a
footnote.
