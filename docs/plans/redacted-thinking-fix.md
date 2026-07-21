# Plan: ROADMAP item 1 — round-trip Anthropic `redacted_thinking` blocks

**Status: ready to implement, verified against the tree 2026-07-20 (post-PR #12).**
One small code increment (worktree + PR). The finding this fixes — my previous
plan's acknowledged omission: `AnthropicStreamParser.consume` handles
`content_block_start` only for `type == "tool_use"` (guard at ~line 153 returns
`[]` otherwise), so a `redacted_thinking` block is silently dropped. Anthropic
requires thinking blocks — including redacted ones — replayed verbatim in
tool-use loops; a conversation that triggers one breaks on its next request.
If a step conflicts with the tree, stop and say so; do not improvise.

## The design in one paragraph

A `redacted_thinking` block arrives as `content_block_start` with
`content_block.type == "redacted_thinking"` and an opaque `data` string (no
deltas follow for it). We carry it as reasoning-entry *metadata* — the channel
vocabulary the bridge already uses — under an `anthropic.`-prefixed key, which
means `TranscriptArchive.replay(to:)`'s existing prefix filter already strips it
on a provider switch with **zero changes to the archive**. The encoder emits it
back as a `{"type": "redacted_thinking", "data": ...}` block in the assistant
message. Multiple blocks per response are legal, so the metadata value is a
JSON-encoded array of data strings, appended in arrival order.

## 1. Parser (`Sources/Executors/StreamParsing.swift`)

In `AnthropicStreamParser.consume`, `content_block_start` case: before the
existing `guard type == "tool_use"`, add a branch — if
`block["type"] as? String == "redacted_thinking"`, read
`block["data"] as? String` (missing/empty → return `[]`, tolerate) and emit:

```swift
events.append(.reasoning(text: "", signature: nil,
    metadata: ["anthropic.redacted_thinking": data]))
```

No new `ExecutorEvent` case; the existing `.reasoning` metadata channel carries
it. **Test** (`StreamParsingTests`): a fixture line with a `redacted_thinking`
block start yields exactly that event; a `redacted_thinking` start missing
`data` yields no event and no throw.

## 2. Bridge (`Sources/Executors/AnthropicExecutor.swift`, `ExecutorChannelBridge`)

The bridge's `.reasoning` case already forwards metadata via `.updateMetadata`,
but each call *replaces* keys. Multiple redacted blocks must accumulate: keep a
private `var redactedThinkingData: [String] = []` in the bridge; when incoming
metadata contains `anthropic.redacted_thinking`, append the value, and emit the
metadata update with the key's value as the **JSON-encoded array** of all
collected strings (encode with `JSONEncoder` — it's `[String]`). Neutral
`signatureProvider` stamping stays as is. **Test**: two redacted blocks through
the bridge → final `.updateMetadata` carries a JSON array of both, in order.

## 3. Encoder (`ExecutorRequestEncoding.anthropicMessages`)

In the `.reasoning` entry case: currently it requires a signature and emits one
`thinking` block. Extend: independently of the signature, if
`reasoning.metadata["anthropic.redacted_thinking"] as? String` decodes as
`[String]`, append one `["type": "redacted_thinking", "data": <element>]`
block per element to `assistantBlocks` **before** the `thinking` block (order
within the entry is an approximation of arrival order; note it in a comment —
Anthropic validates block presence and content, and this preserves
per-response ordering of redacted blocks among themselves). The
ownership guard stays: only entries whose `signatureProvider` is `anthropic`
are considered at all. **Tests**: an archive containing a reasoning entry with
two redacted strings + a signed thinking segment encodes to an assistant
message with two `redacted_thinking` blocks then one `thinking` block; a
replay to `deepseek` strips the metadata (existing prefix filter — assert it
to lock the behavior).

## 4. OpenAI encoder — explicitly nothing

`openAIMessages` ignores `anthropic.*` keys already (ownership guard on
`signatureProvider`); confirm with the replay-strip test above, change nothing.

## Verification and DOD

- `swift test` green on macOS; iOS destination build green.
- New tests: parser (2), bridge (1), encoder round-trip + strip (2).
- ENGINEERING.md: one sentence in the executors section — redacted thinking
  blocks round-trip via reasoning metadata.
- ROADMAP: delete item 1, renumber; delete this plan (absorption rule).

Out of scope: everything else. No live-provider verification is required —
triggering a real redacted block is not deterministic; the wire shape is
documented by Anthropic and fixture-tested here. Note that honestly in the PR.
