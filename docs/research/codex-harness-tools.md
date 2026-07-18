# Codex's tool harness (open source, read from the code)

**Last verified: 2026-07-17**, against a fresh shallow clone of
[openai/codex](https://github.com/openai/codex) `main` (Rust workspace in
`codex-rs/`). Unlike the Claude Code findings
([agent-harness-builtin-tools.md](agent-harness-builtin-tools.md)), everything here
is read from source, not docs — file paths cited so it can be re-checked. Codex moves
fast; expect drift.

Codex CLI is the only frontier-lab agent harness whose implementation we can actually
read. It powers Codex CLI, the ChatGPT desktop Codex integration, and (via
`app-server`) the IDE extensions — one Rust core, several frontends. That layering is
itself a finding: the agent core is a **library with a protocol**, and every UI is a
client. (OpenAI's ChatGPT Work desktop agent is not in this repo; what's shared is the
core architecture.)

---

## The headline: Codex has almost no tools

Where Claude Code ships ~40 built-in tools, Codex's model-visible tool set is
genuinely minimal. Assembled per turn in
`codex-rs/core/src/tools/spec_plan.rs` (`add_shell_tools`,
`add_core_utility_tools`, `add_collaboration_tools`, `add_mcp_resource_tools`):

| Tool | What | Source |
|---|---|---|
| `exec_command` | THE tool. Runs a command **in a PTY**, returns output or a session ID for ongoing interaction | `tools/handlers/shell_spec.rs` |
| `write_stdin` | Sends keystrokes to a running `exec_command` session, returns recent output | same |
| `shell_command` | Legacy non-PTY variant (string script, `workdir`, `timeout_ms` default 10,000 ms); kept dispatch-only when unified exec is active | same |
| `apply_patch` | All file edits, in a custom diff format | `tools/handlers/apply_patch*` |
| `update_plan` | Step-by-step plan with one `in_progress` step | `tools/handlers/plan_spec.rs` |
| `view_image` | Load a local image into context as a data URL | `tools/handlers/view_image_spec.rs` |
| `request_user_input` | Ask the user a question (experimental, config-gated) | `tools/handlers/request_user_input*` |
| `request_permissions` | Model requests elevated permissions mid-task (feature-gated) | `tools/handlers/request_permissions.rs` |
| `get_context_remaining` / `new_context_window` | Token-budget introspection and fresh-window request (feature-gated) | `tools/handlers/` |
| `tool_search` | Deferred-tool discovery — same pattern as Claude Code's ToolSearch, used for connector/MCP tools (spec examples name Google Drive) | `tools/handlers/tool_search_spec.rs` |
| `list_mcp_resources` / `list_mcp_resource_templates` / `read_mcp_resource` | MCP resources, only registered when servers are configured | `spec_plan.rs` |
| multi-agent suite | `spawn_agent`, `send_message`, `wait_agent`, `interrupt_agent`, `list_agents` (v2, feature-gated) | `tools/handlers/multi_agents_v2*` |
| `web_search` | Server-side tool on the Responses API, not executed locally | `core/src/web_search.rs`, `spec_plan.rs` |

**There is no read-file tool, no grep tool, no glob tool, no write-file tool.** The
model reads files with `sed -n '1,200p' file` through the shell, searches with
ripgrep/grep through the shell, and writes only through `apply_patch`. (The
`read_file` strings in the repo are MCP test fixtures for a filesystem MCP server —
`tools/handlers/mcp.rs` tests — not built-ins.) `codex-rs/file-search` is fuzzy
filename search for the TUI's `@`-mentions, a UI feature, not a model tool.

This is the opposite philosophy from Claude Code, and both work:

- **Claude Code**: many typed tools, each with its own budget, permission surface,
  and recovery hints. The harness understands *what* the model is doing (reading vs
  editing vs searching) and can enforce read-before-edit, path rules, gitignore.
- **Codex**: one general executor plus a structured patch format, wrapped in an
  **OS-level sandbox** that makes the executor safe. The harness doesn't know what
  the command does; the sandbox bounds what it *can* do. Safety lives in policy, not
  in tool granularity.

## Mechanics worth stealing

**PTY-first, session-based exec.** `exec_command` params
(`tools/handlers/shell_spec.rs`): `cmd` (string), `workdir`, `tty` (allocate a PTY),
`yield_time_ms` — "Wait before yielding output. Defaults to 10000 ms; effective
range is 250–30000 ms" — and `max_output_tokens` ("Defaults to 10000 tokens").
A command that outlives the yield window returns a **session ID** instead of
blocking; the model then polls/interacts via `write_stdin`. So "timeout" isn't
failure — it's a handoff to interactive mode. Claude Code reinvented this as
auto-backgrounding; Codex designed it in from the start. Default command timeout for
the legacy path: `DEFAULT_EXEC_COMMAND_TIMEOUT_MS = 10_000` (`core/src/exec.rs:58`)
— strikingly shorter than Claude Code's 2 minutes, because yielding is cheap when
sessions persist.

**Token-denominated output budgets.** Truncation is measured in *tokens*, not
characters: `DEFAULT_MAX_OUTPUT_TOKENS: usize = 10_000` (`unified_exec/mod.rs:70`),
`TruncationPolicy::Tokens(n) | Bytes(n)` with **middle truncation**
(`truncate_middle_with_token_budget`, `utils/output-truncation/`), policy taken per
model from `model_info.truncation_policy`. Head+tail preserved, middle elided —
build output and test runs put the signal at both ends.

**Edits as a declarative patch.** `apply_patch` takes a stripped-down file-oriented
diff ("V4A": `*** Begin Patch / *** Update File: path / @@ context / - / + / *** End
Patch`), parsed by a real grammar (`apply_patch.lark`) and applied atomically —
add/update/delete/rename in one call. Registration is per-model
(`model_info.apply_patch_tool_type`); for some models it's a freeform/grammar tool
rather than JSON function-calling. Contrast with Claude Code's Edit
(old_string/new_string + read-before-edit): apply_patch trades harness-enforced
safety checks for atomic multi-file batches and model-native diff fluency.

**Safety = sandbox × approval policy, two orthogonal axes**
(`protocol/src/protocol.rs`):

- `SandboxPolicy`: `read-only` (optional network) · `workspace-write` (read
  everything, write only cwd + writable roots) · `external-sandbox` ·
  `danger-full-access`. Enforced with **Seatbelt (`sandbox-exec`) on macOS**,
  Landlock+seccomp on Linux, a bespoke sandbox on Windows.
- `AskForApproval`: `untrusted` (auto-approve only known-safe read-only commands —
  an allowlist classifier, `is_safe_command()`) · `on-request` (default — **the
  model decides when to ask**, and can run commands outside the sandbox by
  requesting escalation) · `granular` (per-category booleans) · `never`.

The default posture is inverted from Claude Code's: Claude Code default-prompts and
allowlists its way down; Codex default-sandboxes and lets the model request
escalation when a command genuinely needs it (e.g. network). Also present:
`execpolicy` (a Starlark-based command classifier) and per-connector
`AppToolPolicy` (`codex-rs/connectors/`) — connectors/apps with tool-level policy,
matching the Cowork "connectors" pattern.

**Context husbandry as tools.** `get_context_remaining` lets the model *ask* how
much window is left; `new_context_window` lets it request a fresh one; compaction
lives in core (`compact*.rs`, including remote compaction variants). Codex treats
the context budget as a first-class resource the model can observe — Claude Code
keeps that invisible to the model.

**Assembly is dynamic and layered.** The per-turn tool list depends on: model info
(which shell type, whether apply_patch, truncation policy), feature flags, approval
config, whether MCP servers are connected, whether connectors are present, and the
session type (a "guardian reviewer" session gets only exec + view_image). Exactly
the registry pattern our app needs — tools are *composed per turn*, not a static
list.

## What this means for a neutral harness (observations)

- The two harnesses disagree on tool granularity but agree on everything else:
  per-result output budgets stated in the tool schema, middle-or-paged truncation
  with recovery instructions, MCP for extensibility with deferred loading past a
  threshold, an approval/sandbox axis separate from the tool axis, and plan/task
  tools to keep the model oriented.
- Codex's minimal set exists partly *because* its models are RL-trained on
  `exec_command`/`apply_patch`. A neutral app serving eleven providers can't assume
  any model is trained on its exact tool shapes — which argues for the Claude Code
  style: more, simpler, conventionally-named typed tools (every serious model has
  seen read/write/grep-shaped tools), plus schema adaptation per provider.
- For a non-developer product, typed tools also carry the UX: a `read_file` call
  renders as "Read report.docx" trivially; an opaque `sed -n '1,200p'` does not
  (Codex's TUI special-cases common commands to render them friendly —
  `command_canonicalization.rs` — extra machinery we'd need if we went shell-first).
