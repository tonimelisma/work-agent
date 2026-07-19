# Plan: the tool layer — native tools and MCP, modular

**Status: proposal, 2026-07-17.** Toni asked for this plan ("explain what a flexible
tool API for the current macOS app could look like… create a detailed plan to
implement all of these"). It is not an increment in flight: no FR IDs are assigned
here, and building any phase still requires its own DOR with explicit go-ahead
(CLAUDE.md). Where this plan needs a requirement that doesn't exist yet, it says so
under **Open questions** instead of inventing one.

**Update 2026-07-17:** Toni answered four of the open questions; his words are quoted
inline where each lands. The biggest correction: this plan originally scoped all file
tools to user-approved folders (NSOpenPanel + security-scoped bookmarks). Toni: *"We
don't have folders. Permissions come later."* — there is no folder-grant model; file
tools operate on ordinary paths, and the permission/approval design is deferred
wholesale. The `effect` field stays on `ToolSpec` (it's one enum and makes the later
retrofit a policy change), but nothing enforces anything yet.

**Update 2026-07-18:** the Foundation Models adaptation POC now passes all bounded
technical gates, including live Apple-session cycles for DeepSeek, Google and
Anthropic and a live provider switch. Toni accepted the three-layer hybrid and macOS
27 minimum: the host-owned policy contract below belongs in the native Swift runtime
SPM package, bridged to `FoundationModels.Tool`/`GenerationSchema`, while provider
serialization belongs in `LanguageModelExecutor` conformances. See ADR-0006 and
[foundation-models-adaptation.md](../research/foundation-models-adaptation.md).

Grounding: [agent-harness-builtin-tools.md](../research/agent-harness-builtin-tools.md)
(Claude Code/Cowork, the ~40-tool typed style) and
[codex-harness-tools.md](../research/codex-harness-tools.md) (Codex, the
shell-plus-patch style). The codebase today is an unmodified SwiftUI template
(ENGINEERING.md), so this plan builds on the specs, not on existing code — it slots
into ROADMAP increments 4–6 and depends on ADR-0006 (the agent loop) for its wire-level
half.

---

## 1. Which philosophy, and why

Two proven designs exist. Codex: one PTY executor plus a patch format, safety from an
OS sandbox. Claude Code: many typed tools, safety from per-tool permissions.

**This plan proposes the typed-tool style.** Three reasons, all specific to us:

1. **Neutrality.** Codex's minimal set works because its models are RL-trained on
   `exec_command`/`apply_patch`. Our sixteen models from eleven vendors share no such
   training — but all of them have seen read/write/search-shaped tools. Simple, typed,
   conventionally-named tools are the lowest-variance interface across vendors
   (FR-001), and per-provider schema quirks stay in the adapters (NFR-001).
2. **Legibility.** FR-065 requires showing tool calls user-friendly. A typed
   `read_file(path:)` renders as "Read Q3 report.docx" for free; an opaque shell
   string needs a command-parsing layer (Codex ships one) that we'd have to build and
   that non-developers still wouldn't trust.
3. **No shell dependency.** Our users' work lives in documents and folders, not
   terminals; a shell tool needs an isolation story we've deliberately deferred
   (ROADMAP). Typed tools let increment 5 ship real capability without opening that.

What we take from Codex anyway: **token-denominated output budgets with middle
truncation**, **per-turn dynamic tool assembly**, and the **sandbox-vs-approval
axes as separate concepts** for when shell/exec eventually lands.

## 2. The core abstraction

**Superseded in part, 2026-07-18:** the separate host tool protocol sketched below
is replaced by the north-star tool design in [runtime-api.md](runtime-api.md) §3 —
tools are plain `FoundationModels.Tool`s; the runtime instruments them via generic
wrappers and carries effects/idempotency as `ToolAnnotations` data (policy table →
modifier → optional refinement conformance → MCP hints → conservative default).
What survives from this section unchanged: the runner pipeline (§ trace-before-
budget below), the output budgets, the effect taxonomy's *content*, and every
per-tool implementation spec in §3. The increment that builds the tool host
rewrites this section to match.

One host contract, everything runs through it — built-ins and MCP tools alike.
The runner, effect/resource metadata and Apple bridge live in the native
Swift runtime SPM package. Product-specific tool implementations and authorization
policy stay in the Work Agent app and conform through the package's public API.

```swift
/// A capability the agent can invoke. Built-in or remote (MCP) — the loop can't tell.
protocol Tool: Sendable {
    var spec: ToolSpec { get }
    func invoke(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput
}

/// Provider-neutral description. Adapters serialize this to each vendor's wire shape.
struct ToolSpec: Sendable {
    let name: String                  // "read_file" — snake_case, conventional
    let description: String           // written for the model, includes limits & recovery hints
    let parameters: JSONSchema        // minimal own Codable type: object/string/number/bool/array/enum
    let effect: ToolEffect            // .readOnly / .writesWorkspace / .consequential / .network
    let outputBudget: OutputBudget    // enforced by the runner, stated in the description
}

struct ToolContext: Sendable {
    let workspace: Workspace          // path-resolution root (cwd-like); no grants — "permissions come later"
    let trace: TraceRecorder          // FR-063 sink — records raw args + full output, always
    let readLedger: FileReadLedger    // which paths this conversation has read (edit precondition)
    let modelCapabilities: ModelCapabilities  // vision? from the models.dev registry (ADR-0005)
}

struct ToolOutput: Sendable {
    var blocks: [Block]               // .text(String) | .image(Data, mime)
    var isError: Bool
    // Full output goes to the trace; the *runner* decides what the model sees.
}
```

Two deliberate absences: no permission logic inside tools (`effect` is data; the
runner decides what to do with it — approvals are deferred, "specific tool approvals
will come later," but the field exists from day one so retrofitting is a policy
change, not a refactor), and no provider types anywhere in `Tools/` (the compile-time
enforcement of FR-001: `Tools/` must not import the provider layer).

**The package boundary (decided with ADR-0006).** `Tool`/`ToolSpec`/`ToolRunner`, the
Foundation Models bridge, runtime policy and the MCP client depend only on the runtime
package and Apple frameworks — never on the app's catalog, Keychain, task store or UI.
The app injects those concerns through protocols (`TraceRecorder` is the pattern).
Foundation Models `Transcript` and `GenerationSchema` replace the older proposed
conversation/extras/schema lookalikes; provider-specific state stays in Apple transcript
metadata and typed reasoning signatures with explicit ownership on failover.

### The runner: where the context window is defended

Tools return honest, complete output. A single `ToolRunner` sits between the loop and
every tool and applies, in order:

1. **Record** the invocation to the trace — raw arguments, full output, timing,
   error — before any truncation (FR-063: display never limits what's persisted).
2. **Budget** the model-facing view. Token estimate (chars/4 heuristic first; a real
   tokenizer is per-provider and not worth it yet). Over budget → the tool's declared
   strategy:
   - `.pagedView` (reads): first page + `PARTIAL view: showing lines 1–N of M. Use
     offset/limit to continue.` — the Claude Code pattern.
   - `.middleTruncate` (exec-like, logs): head + tail preserved, elision marker with
     omitted-line count — the Codex pattern.
   - `.spill`: full output already in the trace store; model gets a short preview +
     an id it can re-read paged via `read_trace_output` (nothing writes to the user's
     folders for the harness's own bookkeeping).
3. **Time-box** via structured-concurrency cancellation (per-tool default in spec).

Every limit is also *stated in the tool description*, and every truncation names the
recovery move in its notice — both harnesses converged on teaching the model the way
out, and it's the cheapest reliability win in the whole design.

### The registry: per-turn assembly

```swift
struct ToolRegistry {
    func tools(for turn: TurnContext) -> [any Tool]
}
```

Composed fresh each turn from: built-ins enabled by settings; MCP servers currently
connected (each contributing adapted tools); and model capability gates from the
registry snapshot — e.g. image-reading only when the model has vision, and
provider-exclusive server-side tools (Anthropic/OpenAI hosted web search) injected by
the *adapter*, not the registry, since they execute vendor-side (FR-060: expose
exclusives; FR-001: the neutral layer doesn't know about them). This is Codex's
`spec_plan.rs` pattern, and it's what makes the whole layer modular: adding a tool
source (built-in, MCP server, future connector) is one registry input, nothing else
changes.

### The provider seam

The accepted ADR-0006 design makes `LanguageModelSession` own the basic
model/tool/model cycle. The two shipped
transports conform to `LanguageModelExecutor`, and a wrapper exposes each richer host
tool as `FoundationModels.Tool`. The host runner still owns trace-before-budget,
timeouts, recoverable error output, effects, idempotency and resource scheduling;
Apple's tool protocol is not the authorization or durability boundary.

Each executor owns both directions between Apple's `Transcript`/tool definitions and
its wire format: Anthropic `tools`/`input_schema` and `tool_use` blocks; OpenAI
`tools[].function`, `tool_calls` and tool-role messages. Tool results return through
Apple transcript entries, not an app-owned message hierarchy. This is exactly where
increment 6's cold-provider test bites, which is why the conformance fixtures must be
right before the tools are many.

## 3. The built-in tools, one by one

There is no folder-grant model — *"We don't have folders. Permissions come later."*
File tools take ordinary absolute paths (canonicalized: `URL.standardizedFileURL`,
symlinks resolved), with a per-task working directory as the relative-path base.
Consent, scoping, and approvals are all part of the deferred permissions design; the
trace (FR-063) is the accountability mechanism in the meantime. Names are
model-facing; the UI shows friendly verbs, never these identifiers.

**`read_file`** — the workhorse.
`path`, optional `offset`/`limit` (lines). Implementation: open via `FileHandle`,
stream and split lines incrementally — never `String(contentsOf:)` (a 2 GB log would
OOM before budgeting). Defaults stolen verbatim from Claude Code: 2,000 lines max
per call, 2,000 chars per line (marked truncated), then the runner's token ceiling
with paged partial view. `cat -n`-style line numbers so edits can anchor. Type
sniffing by extension + magic bytes: UTF-8 text (with latin-1 fallback) → lines;
image → downscale via `CGImageSourceCreateThumbnailAtIndex` to fit model image
limits, emit `.image` block, gated on vision capability; PDF → PDFKit
`documentAttributes` + per-page text, whole if ≤10 pages else require a `pages`
range (≤20); **.docx → text, in increment 5** (Toni: *"docx text in increment 5"*) —
implementation: unzip the OOXML container (a .docx is a zip; use the
`Compression`/`libarchive` route or a small zip dependency), parse `word/document.xml`
with `XMLParser`, emit paragraph text with basic structure (headings by style id,
tables as markdown rows); .xlsx/.pptx stay honest "can't read this yet" errors until
a later increment.
Empty file and past-EOF offset return distinct notices, not errors.

**`list_folder`** — because we have no `ls`.
`path`, optional `recursive` (depth-capped at 3). `FileManager` enumerator returning
name, kind, size, modified date; skip hidden by default; cap 300 entries with
truncation flag + "narrow with find_files". Sorted folders-first, then mtime.

**`find_files`** — glob.
`pattern` (`**/*.docx` style), `path` root. `FileManager.enumerator` walk matching
against relative paths with an `fnmatch`-based matcher (`FNM_PATHNAME` semantics; a
~50-line wrapper — no dependency). Sort by mtime, cap 100 + truncation flag (Claude
Code's numbers). No gitignore semantics — meaningless for document folders.

**`search_files`** — content grep.
`pattern` (regex), `path`, optional `glob` filter, `mode`: `files_with_matches`
(default) | `content` (file:line + line text) | `count`. Implementation decision:
**native Swift first, no bundled ripgrep.** Walk candidate files (text-sniffed,
skip >2 MB), search with `NSRegularExpression` line-by-line, early-exit at 100
matches. Rationale: our corpus is a person's documents folder, not a monorepo;
shipping/notarizing a Mach-O `rg` universal binary is real packaging surface for
performance we don't yet need. Measured against a realistic folder in the increment;
if it's slow, bundling rg is a contained swap behind the same spec (noted as the
revisit trigger, not a maybe).

**`write_file`** — create or replace.
`path`, `content`. Atomic (`Data.write(options: .atomic)`), creating intermediate
directories as needed. Overwrite requires the path in the
`FileReadLedger` (Claude Code's read-before-write rule — cheap and prevents the
worst blind-clobber failure). Effect class `.writesWorkspace`; the trace records the
*previous* content of overwritten files (bounded, say ≤4 MB), which is what makes a
future undo/review UI possible without designing it now.

**`edit_file`** — surgical change.
`path`, `old_string`, `new_string`, `replace_all`. Exact-match, uniqueness-or-
`replace_all`, read-before-edit from the ledger — the full Claude Code contract,
including its error messages, which are half the tool's value (each failure tells
the model the fix). Chosen over Codex's `apply_patch` because patch-fluency is
GPT-training-specific; exact-string-replace is model-agnostic.

**`ask_user`** — the human tool.
1–4 questions, 2–4 options each, free-text always allowed. Async: the invocation
suspends on a `CheckedContinuation` held by the task's state machine, UI renders a
question card, answer resumes the loop. Interacts with NFR-006 (UI responsive while
suspended) and gives FR-065's trace view a natural "asked you / you answered" beat.

**`update_plan`** — task-progress structure.
Codex's shape: ordered steps, exactly one `in_progress`. Costs an afternoon and is
the direct data source for the increment-4 "watch a task run" UI
and for FR-065's friendly display. In: worth it.

**`fetch_url`** — web page → **paged markdown** (decided: Toni picked the paged
option; no extraction model, no second model call).
`URLSession` with: HTTPS upgrade; deny private/link-local/metadata IPs *after* DNS
resolution (SSRF); cross-host redirects surfaced back to the model, not followed
(both harnesses do this); 5 MB response cap; HTML→Markdown via SwiftSoup traversal
(one small MIT dependency; WebKit rendering is heavier and drags in JS execution we
don't want). Then normal budgeting: paged view. 15-minute in-memory cache. Effect
`.network`.

**`web_search`** — **both paths** (Toni: *"Both"*). (a) Provider-hosted search
tools (Anthropic's `web_search`, OpenAI Responses search, Gemini grounding) exposed
through their adapters where the vendor offers one — these execute server-side, so
the adapter injects the vendor's tool declaration and maps its result blocks back
into the neutral trace; FR-060 territory. (b) A neutral `web_search` built-in
backed by a search API (Brave or Exa — pick at implementation time by pricing/ToS)
with its own key in Settings, registered for models whose provider has no hosted
search — and available as an override for all. Registry rule: a model gets exactly
one `web_search` tool, hosted preferred, neutral otherwise.

**Explicitly not in this plan:** shell/exec (needs the isolation ADR first;
Codex's Seatbelt `sandbox-exec` usage is the working precedent on macOS, and the
Tool protocol accommodates it later as just another tool), subagents (needs
multi-loop infrastructure; the protocol doesn't block it), computer
use/Accessibility (deferred per ROADMAP), connectors with OAuth (deferred until a
real task needs one — but see MCP below, which is how they'll arrive).

## 4. MCP as a tool source, not a feature

MCP servers plug in at the registry, and the loop never knows:

```swift
final class MCPServerConnection {           // one per configured server
    // stdio transport: Process + pipes, JSON-RPC 2.0, initialize → tools/list → tools/call
    // http transport: URLSession, Streamable HTTP
    func discoveredTools() async throws -> [MCPTool]   // each wraps one remote tool
}
struct MCPTool: Tool {
    // spec: name namespaced "\(serverLabel).\(toolName)"; parameters passed through
    //       (JSON Schema must survive GenerationSchema conversion — strict subset,
    //        measured; unsupported keywords go through the degradation ladder in
    //        runtime-api.md §4 rather than being silently flattened)
    // invoke: tools/call; content blocks mapped to ToolOutput; isError passthrough
    // effect: .consequential by default — a remote tool is assumed side-effectful
    //         unless its annotations say readOnlyHint (MCP tool annotations, trust-but-verify)
}
```

Implementation choice: evaluate the **official `modelcontextprotocol/swift-sdk`**
first (it exists and is actively maintained; verify at increment time that it covers
client role + stdio + Streamable HTTP at our minimum macOS). If it fits, wrap it; if
not, the client subset we need (initialize/list/call/notifications) is small enough
to hand-roll against the spec. Either way the seam is `MCPServerConnection`, so the
choice is swappable and needs no ADR until proven otherwise — the *decision to ship
MCP at all* gets the ADR.

Product surface, per PRODUCT.md ("not a GUI for editing MCP JSON"): v1 config is a
developer-facing file/hidden pane for Toni-stage use; end users eventually get
curated connectors that are *implemented as* MCP servers and never described in
those words. Deferred tool loading (both harnesses' ToolSearch pattern) becomes
worthwhile only past ~30–40 tools; the registry's assembly step is where it slots
when needed. Same for MCP resources/prompts: skip until a concrete need.

## 5. Phasing — mapped to the existing roadmap

No new increments invented; this fills in the tool-shaped parts of increments 4–6.

- **With increment 4** (loop + first model call): `ToolSpec`/`Tool`/`ToolRunner`/
  `TraceRecorder` types and the adapter serialization for the increment's provider(s)
  — the loop needs tool wiring even before real tools, and `update_plan` + `ask_user`
  can ship here as the only tools, exercising the whole path with zero filesystem risk.
- **Increment 5** (first tools, tested): Workspace + bookmarks; the six file tools;
  `fetch_url`. Each tool: unit tests against fixture folders (large file, 100 MB log,
  10k-char single line, binary, empty, symlink escape, non-UTF-8), budget tests, and
  a live run in the app (DOD requires exercised, not inferred). No approval gate:
  *"Permissions come later"* — writes run ungated and land in the trace; the
  `effect` classification exists so the later permissions increment is policy, not
  refactoring.
- **Increment 6** (second provider, cold): contract-test suite runs every tool spec
  through every adapter — same neutral `ToolCall` in, correct vendor wire out, and a
  recorded multi-tool conversation replayed against both providers. This is where the
  tool layer proves FR-001/NFR-001 or falsifies them.
- **After** (own increment, ordered by Toni): MCP connection + first real server;
  `web_search` per open Q2; office-file reading per open Q5.

Traceability: when each phase's DOR runs, its behaviors get FR IDs drafted from
Toni's actual words (this document deliberately assigns none); code carries
`// REQ:` comments per CLAUDE.md.

## 6. Open questions — answered 2026-07-17, remainder below

Answered by Toni (his words):

1. ~~Approval UX for writes~~ — *"We don't have folders. Permissions come later."*
   No folder-grant model, no write gate; the whole permissions design is deferred.
2. ~~Web search backend~~ — *"Both."* Hosted-per-provider plus a neutral
   API-key-backed built-in; one search tool per model, hosted preferred.
3. ~~`fetch_url` extraction model~~ — paged markdown, no extraction call.
5. ~~Office formats~~ — *"docx text in increment 5."* Sheets and slides later.

Answered 2026-07-18 (Toni: *"I generally prefer native Swift"*, then "do it" on the
recommendations):

4. ~~Bundled ripgrep~~ — **native Swift search**, no bundled binary: `FileManager`
   walk + Swift's own `Regex`, streaming line-by-line with early exit. Users'
   corpora are document folders, not monorepos. The measurement trigger in §3
   stays as the escape hatch: if a realistic corpus measures painfully slow in
   increment 5, swapping the engine behind the same tool spec is contained.
6. ~~Tool granularity~~ — **keep the six file tools.** Conventionally-shaped
   read/write/grep/glob-style tools are what every model is trained against —
   necessary since none of our eleven vendors' models are RL-trained on a bespoke
   set — and each call renders as a legible UI line (FR-065) for free.
7. ~~Neutral search API~~ — **Brave.** A conventional SERP behaves identically to
   the provider-hosted search tools, so the "one search tool per model, hosted
   preferred" rule gives every model the same experience; Exa's semantic search
   and content-return would make the fallback *different*, and its content
   feature duplicates `fetch_url`. Verify pricing/ToS at implementation time;
   that check may change the vendor, not the architecture.

Nothing in this plan now requires shipping a foreign binary: SwiftSoup, the MCP
swift-sdk, and ZIPFoundation (docx) are all pure Swift.

No questions remain open. The next conversation this plan needs is a DOR for
whichever increment builds its first phase.
