# Built-in tools in agent harnesses (Claude Code / Claude Cowork)

**Last verified: 2026-07-17.** Sources: the official
[Claude Code tools reference](https://code.claude.com/docs/en/tools-reference),
the [Agent SDK overview](https://code.claude.com/docs/en/agent-sdk/overview),
GitHub issues on the `anthropics/claude-code` repo, and first-hand observation of a
live Claude Code session on 2026-07-17 (the tool schemas the model actually sees, and
the harness's truncation behavior triggered in practice). First-hand observations are
labeled as such — they reflect one version on one day and rot fastest.

Why this doc exists: Work Agent needs its own tool harness, and the design questions —
what tools, what defaults, how to keep a single `Read` from eating the context window —
have all been answered in production by Claude Code. The other production answer, read
from source rather than docs, is in [codex-harness-tools.md](codex-harness-tools.md). Cowork is the same harness in a
desktop skin, which makes it the closest existing product to what we're building.

---

## The shape of the thing

A coding/work agent is three parts: a **model loop** (send conversation + tool schemas,
get back tool calls, execute, append results, repeat), a **tool set**, and — the part
everyone underestimates — **context-budget discipline** on every tool result. The tools
themselves are mostly thin wrappers over ripgrep, the filesystem, and a subprocess
spawner. The engineering is in the limits.

Claude Cowork is confirmed to be the same architecture: it's built on the Claude Agent
SDK, "the same agentic architecture that powers Claude Code, with no terminal required"
([VentureBeat](https://venturebeat.com/technology/anthropic-launches-cowork-a-claude-desktop-agent-that-works-in-your-files-no),
[Anthropic product page](https://www.anthropic.com/product/claude-cowork)). Anthropic
reportedly built Cowork in about a week and a half on top of the existing harness. The
lesson for us: the harness is the product platform; the "app" is a shell around it.

---

## How the context window is protected (the 900k-token question)

Every tool result passes through a layered defense. This is the single most important
design pattern in the whole harness:

1. **Per-tool defaults sized for the common case.** `Read` returns up to 2,000 lines
   by default; individual lines are truncated at 2,000 characters (first-hand: the
   tool schema says "Reads up to 2000 lines by default"; confirmed in
   [issue #6910](https://github.com/anthropics/claude-code/issues/6910)). A 2,000 ×
   2,000 worst case is ~4 MB, so the line/char caps alone aren't sufficient — hence
   layer 2.

2. **A token-based ceiling with graceful paging, not errors.** Per the
   [tools reference](https://code.claude.com/docs/en/tools-reference): when a
   whole-file read exceeds the token limit, Read returns the *first page* plus a
   `PARTIAL view` notice telling the model how much it got and how to continue with
   `offset`/`limit` parameters. An explicit-range read that's still too big returns an
   error. A range containing an absurdly long single line fails fast without loading
   it (pre-v2.1.208 this could exhaust memory — a bug worth not reimplementing) and
   the error redirects the model to Grep. The pattern: **never silently drop content,
   never blow the budget — return a partial view plus instructions for getting more.**

3. **Spill-to-disk above a threshold.** Bash output over 30,000 characters (default;
   `BASH_MAX_OUTPUT_LENGTH`, hard ceiling 150,000) is written to a file in the session
   directory; the model receives the file path plus a short preview, and uses
   Read/Grep on the file if it needs the rest. First-hand (2026-07-17): the same
   mechanism covers other tools — an 83 KB WebFetch result in our session came back as
   `<persisted-output> Output too large (83.4KB). Full output saved to: <path>` with a
   2 KB preview. [Issue #19901](https://github.com/anthropics/claude-code/issues/19901)
   cites `DEFAULT_MAX_RESULT_SIZE_CHARS = 50_000` as the general persist threshold.

4. **Search tools default to references, not content.** Grep's default output mode is
   `files_with_matches` — paths only, no matched lines. Glob caps results at 100 files
   (sorted by modification time, with an explicit truncation flag). The model
   navigates by pointer and reads only what it decides it needs.

5. **Lossy-by-design web ingestion.** WebFetch never hands the model the raw page: it
   converts HTML to Markdown, truncates to a fixed character budget, then runs the
   model-supplied extraction prompt against it **using a separate small, fast model**,
   returning only that model's answer. WebSearch returns titles and URLs only — reading
   a result requires a follow-up WebFetch. So an arbitrary webpage can never dump its
   full weight into the main context.

6. **Subagents as context firewalls.** The Agent tool runs a subagent in its own
   context window; the parent sees only the final text summary, never the intermediate
   tool traffic. A "search the whole codebase" task can burn 100k tokens in the child
   and cost the parent a paragraph.

7. **Deferred tool schemas.** With many MCP servers connected, tool *definitions*
   themselves are a context cost. Claude Code defers them: only names are loaded up
   front, and a `ToolSearch` tool fetches full schemas on demand.

8. **Compaction as the backstop.** When the conversation itself grows too long, the
   harness summarizes older context and continues in a fresh window. This is
   orthogonal to the per-tool limits but completes the picture.

---

## The full built-in tool inventory

From the [tools reference](https://code.claude.com/docs/en/tools-reference), verified
2026-07-17. Grouped by function; "prompts" refers to the default permission mode.

### Filesystem

| Tool | What it does | Key mechanics |
|---|---|---|
| `Read` | File → numbered lines | Absolute paths; default 2,000 lines / 2,000 chars per line; token-limit paging (above). Reads **images** as visual content (resized/recompressed to fit model limits; >500 KB after resize re-encoded as JPEG), **PDFs** (whole if ≤10 pages, else a `pages` range, ≤20 pages/call), **Jupyter notebooks** (cells + outputs). Files only — directories go through `ls` in Bash. No prompt inside the working dir. |
| `Write` | Create or fully overwrite | Overwriting an existing file requires having Read it this conversation (fails otherwise); new files exempt. No append/merge. Prompts. |
| `Edit` | Exact string replacement | `old_string` → `new_string`; no regex, no fuzzy matching. Three gates: read-before-edit (a `PARTIAL view` read doesn't count), exact match (one whitespace char off = miss), uniqueness (else supply more context or `replace_all: true`). Viewing via plain `cat`/`head`/`tail`/`sed -n`/`grep` on a single file also satisfies read-before-edit. Prompts. |
| `NotebookEdit` | Jupyter cell ops | Targets cells by `cell_id`; modes `replace` (default) / `insert` / `delete`. Shares `Edit(...)` permission paths. |
| `Glob` | Find files by name pattern | `**` recursion, `{a,b}` alternation; results sorted by mtime, capped at 100 with truncation flag. Does **not** respect `.gitignore` by default (Grep does — deliberate asymmetry: you may need to *find* an ignored file, but search shouldn't wade through `node_modules`). |
| `Grep` | Search file contents | Built on **ripgrep** (ripgrep regex syntax, not POSIX). Output modes: `files_with_matches` (default), `content` (lines + file:line), `count`. Scoping via `glob` / `type` params; `multiline: true` for cross-line; `head_limit`/`offset` for paging. Respects `.gitignore`; explicit paths override. Invalid patterns return ripgrep's own diagnostic so the model can self-correct. |
| `LSP` | Language-server intelligence | Definitions, references, type info, symbols, call hierarchy; auto-reports type errors after each edit. Inactive until a language plugin is installed. |

### Execution

| Tool | What it does | Key mechanics |
|---|---|---|
| `Bash` | Shell command in a fresh process | **Timeout** 2 min default, model can request up to 10 min (`BASH_DEFAULT_TIMEOUT_MS` / `BASH_MAX_TIMEOUT_MS`). **Output** 30k chars then spill-to-disk (above). No state between calls: env vars don't persist; `cd` carries over only within allowed dirs (else reset + notice); startup aliases/functions captured once at session start. `run_in_background: true` for servers/watchers; a foreground command that hits its timeout is **moved to the background, not killed**. A built-in read-only command set (ls, cat, git status…) runs without prompting; everything else prompts, with `Bash(npm run *)`-style allowlist rules. |
| `PowerShell` | Native PowerShell | Windows-first; opt-in elsewhere. `-ExecutionPolicy Bypass` at process scope. |
| `Monitor` | Background watcher | Runs a script and feeds each output line back as an event mid-conversation, or subscribes to a WebSocket (text frames → events; >1 MiB kills the watch; private/link-local/metadata addresses denied). Uses Bash permission rules. |

### Web

| Tool | What it does | Key mechanics |
|---|---|---|
| `WebFetch` | URL + extraction prompt | HTML→Markdown, truncate, run prompt on a small side model; 15-min cache; HTTP→HTTPS upgrade; cross-host redirects returned to the model instead of followed (SSRF-ish guard); `User-Agent: Claude-User…`. Prompts per new domain, with a preapproved docs-domain set and `WebFetch(domain:x)` rules. |
| `WebSearch` | Query → titles + URLs | Server-side (Anthropic backend); up to 8 internal refinement searches per call; `allowed_domains` / `blocked_domains` (not combinable). **Session cap: 200 calls** including all subagents; at the cap, calls return a "continue with what you have" notice rather than an error that would invite retries. |

### Orchestration

| Tool | What it does | Key mechanics |
|---|---|---|
| `Agent` | Spawn a subagent | Own context window; parent gets final text only. Tool access via `tools` / `disallowedTools` in the agent definition (deny wins); background by default in recent versions, with permission prompts surfaced into the main session. Also does conversation forks. |
| `SendMessage` | Continue/steer a spawned agent | Resumes by ID/name with context intact; also agent-team messaging. A message from another agent is never treated as user consent. |
| `TaskCreate/Get/List/Update`, `TaskStop`, `TaskOutput` | Task checklist + background-task control | Successor to the older `TodoWrite`. `TaskOutput` deprecated in favor of Reading the task's output file. |
| `Workflow` | Scripted multi-subagent orchestration, one consolidated result | |
| `CronCreate/Delete/List`, `ScheduleWakeup`, `RemoteTrigger` | In-session scheduling, self-paced loops, cloud routines | |
| `EnterWorktree` / `ExitWorktree` | Git-worktree isolation for parallel work | |

### User interaction & session

| Tool | What it does | Key mechanics |
|---|---|---|
| `AskUserQuestion` | Multiple-choice clarification | 1–4 questions, 2–4 options each, "Other" always added; optional idle auto-continue timeout. |
| `EnterPlanMode` / `ExitPlanMode` | Read-only planning, then plan approval as an explicit gate | |
| `Skill` | Run a packaged prompt workflow | Skills are markdown + frontmatter (`.claude/skills/*/SKILL.md`) executed through this one tool — extensibility **without adding tool-schema surface**. |
| `ToolSearch` / `WaitForMcpServers` | Load deferred tool schemas on demand / await connecting MCP servers | |
| `Artifact`, `SendUserFile`, `PushNotification` | Publish an HTML/MD page to claude.ai; push files to the user's device; desktop/phone notification | All require Anthropic-hosted infra. |
| `ListMcpResourcesTool` / `ReadMcpResourceTool` | Enumerate/read MCP resources | |
| `ReportFindings` | Structured code-review findings for native rendering | |

### Permission model (cross-cutting)

Tool names double as the permission vocabulary: `allow`/`deny`/`ask` rules of the form
`ToolName(specifier)` — `Bash(npm run *)` command patterns, `Read(~/secrets/**)` /
`Edit(/src/**)` path patterns, `WebFetch(domain:example.com)`, `Agent(Explore)`,
`Skill(deploy *)`. Read-family tools don't prompt inside the working directory but do
outside it. An `Edit` allow implies `Read`; a `Read` deny blocks `Edit` on the same
path. Deny rules are also applied to *recognized* file commands inside Bash
(`cat`, `sed`, …) but not to arbitrary subprocesses — for that there's the OS-level
[sandbox](https://code.claude.com/docs/en/sandboxing) (Seatbelt on macOS): filesystem
write access confined to the working directory, network egress by domain allowlist,
enforced on every child process. Hooks (`PreToolUse`, `PostToolUse`, `SessionStart`,
`Stop`, …) intercept the lifecycle for validation/logging/transformation.

---

## What Cowork adds on top of the same harness

Cowork is the harness re-skinned for non-developers, plus extra effector layers.
From [Anthropic's product page](https://www.anthropic.com/product/claude-cowork) and
[help center](https://support.claude.com/en/articles/13345190-get-started-with-claude-cowork),
plus first-hand observation of a Cowork-style session (2026-07-17):

- **Folder-scoped file access**: the user picks folders; the same Read/Write/Edit/
  Bash tools operate inside that scope.
- **Connectors (MCP under the hood)**: Gmail, Calendar, Drive, Slack, etc. appear as
  namespaced MCP tools (`mcp__<server>__<tool>`), deferred-loaded via ToolSearch.
  Users are never shown "MCP" — they see "connectors." (Same principle as our
  non-negotiable about hiding MCP/AXUIElement from users.)
- **Three-tier effector strategy**, in preference order: **connectors first** (fast,
  precise, API-backed) → **browser automation** via the Claude-in-Chrome extension
  (DOM-level: accessibility-tree reads, refs, form_input) → **computer use** (screen
  screenshots + synthetic clicks/keys) as last resort
  ([help center](https://support.claude.com/en/articles/14128542-let-claude-use-your-computer-in-cowork)).
  First-hand: computer use is gated by per-application grants with **tiered
  restrictions by app category** — browsers are read-only (screenshots yes, clicks
  no — Chrome extension handles interaction), terminals/IDEs are click-only (no
  typing — Bash handles shell), everything else full control. Enforced at the
  harness by frontmost-app checks, not by asking the model nicely.
- **Skills, artifacts, scheduled tasks** as the user-facing packaging of the same
  Skill/Artifact/Cron tools.
- **A safety layer that treats all tool-observed content as data, not instructions**
  (prompt-injection defense), with hard-prohibited action classes (credentials,
  payments, deletions) and confirm-first classes (sending messages, publishing,
  purchases). This is policy in the system prompt plus harness-enforced gates.

## Availability to us: the Agent SDK

The entire harness above ships as a library — `@anthropic-ai/claude-agent-sdk` (npm)
and `claude-agent-sdk` (PyPI): "the same tools, agent loop, and context management
that power Claude Code, programmable in Python and TypeScript"
([SDK overview](https://code.claude.com/docs/en/agent-sdk/overview)). Third-party
apps get the built-in tools, hooks, subagents, MCP, permission rules, and session
resume. Two catches, verified 2026-07-17:

1. **No Swift SDK.** TypeScript and Python only; other languages drive the CLI
   headlessly (`-p --output-format json`). The TS SDK bundles a native Claude Code
   binary. A native macOS app would embed a Node/CLI sidecar or reimplement the
   harness.
2. **API-key auth only, and it's Anthropic-coupled.** The SDK docs state:
   "Anthropic does not allow third party developers to offer claude.ai login or
   rate limits for their products, including agents built on the Claude Agent SDK."
   (Consistent with [provider-subscription-auth.md](provider-subscription-auth.md).)
   More fundamentally, building on this SDK is building on one vendor's harness and
   models — the exact coupling this product exists to avoid. Its value to us is as a
   **reference architecture to learn from**, not a dependency: the tool inventory,
   the limit numbers, and the layered truncation pattern above are the parts worth
   reimplementing provider-neutrally.

---

## Implications for Work Agent (observations, not decisions)

- The context-protection pattern is the transferable core: **every tool result gets a
  budget, oversized results degrade to pointer-plus-preview, and the error/notice text
  teaches the model the recovery move** (offset/limit, Grep, read-the-file). No ADR
  exists for any of this yet; when we design our harness, these numbers are the
  starting point, not gospel — they're tuned for ~200k-token context windows.
- For a non-developer product, Cowork's tiering (connectors → browser → screen) and
  its per-app, per-tier computer-use grants are the closest prior art to our approval
  model.
- Tool names as the permission vocabulary (with parameter-level specifiers) is an
  elegant unification we'd otherwise reinvent badly.

---

## Gap analysis: AgentKit's ToolKit vs the work-assistant benchmarks (2026-07-19)

Cross-referencing this doc's Cowork/Claude Code inventory (and the Codex doc)
against AgentKit's built tools (FR-074–083) and roadmap. The convergent core set
every benchmark ships — ChatGPT's work surface, OpenAI's hosted tools, Manus
included — is seven capabilities: files, web, code execution, office documents,
email/calendar, browser/computer control, plan+ask.

| Capability | Benchmarks | AgentKit status |
|---|---|---|
| Files read/write/edit/find/search | All | Built (FR-074–079); docx read is native where Cowork uses code execution |
| Web fetch + search | All | Built (FR-082/083); Brave path never live-run |
| Ask user + plan tracking | All | Built (FR-080/081) |
| Calendar/contacts/reminders | Cowork via OAuth connectors | Roadmap (ToolKitPIM — local EventKit/Contacts, no OAuth: the differentiated angle) |
| **Email** | Cowork's tier-one connector | **Decided 2026-07-19: "Gmail and Outlook via MCP. No one uses the local mail app. Put them ASAP."** Roadmap item 3 — which pulls the whole MCP foundation up with it. Mail.app-via-Apple-Events rejected |
| **Document creation** | Cowork's document skills via sandboxed code execution — arguably its core work value | **Decided 2026-07-19: "PDFs too" — PDF creation is roadmap item 4** (PDFKit, native, no sandbox needed). docx/xlsx *creation* remains an open recommendation, not decided |
| Code/shell execution | Cowork sandboxed bash; Codex's entire thesis | Parked until an isolation design exists — noting honestly that it also underlies the benchmarks' data-analysis and file-conversion patterns; native PDF creation removes one of those pressures |
| Browser / computer use | Cowork tiers 2–3 | Deliberately absent; the widest capability gap and the most defensible to skip |
| Subagents, skills, scheduling, artifacts, memory stack | Present in Claude harnesses | Non-goals / app-layer; Apple FM 27's "custom skills" may cover the skills niche natively — watch |

Bottom line at the time of writing: four of the seven core capabilities built,
calendar planned, email and PDFs now prioritized at roadmap items 3–4. The two
deliberate absences (code execution, browser/computer control) are the ones where
skipping is strategy rather than lag.
