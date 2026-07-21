# Plan: ROADMAP item 1 — fix the 2026-07-20 review errata

**Status: ready to implement, verified against the tree 2026-07-20.** One code
increment (worktree + PR) fixing all findings from the full-repo review. Each fix
names its file, the exact change, and the test that proves it. Order is the
ranking; do them in order so a partial increment still lands the worst first.
If a step conflicts with the tree, stop and say so; do not improvise.

## 1. `fetch_url`: stop following redirects blindly (SSRF)

`Sources/ToolKitWeb/FetchURLTool.swift`. Today `session.data(for:)` follows
redirects internally, so the SSRF check runs only on the original host and a
302 to an internal address is actually fetched before the post-hoc cross-host
check throws. Replace with a **manual redirect loop**:

- Add a private `NoRedirectDelegate: NSObject, URLSessionTaskDelegate`
  implementing
  `urlSession(_:task:willPerformHTTPRedirectionResponse:newRequest:)` and
  returning `nil` — redirects are never followed by URLSession; the 3xx
  response is delivered to us.
- Fetch with `session.bytes(for: request, delegate: NoRedirectDelegate())`
  (per-task delegate; the injected session itself stays untouched).
- Loop, max 5 hops: on a 3xx status read the `Location` header, resolve it
  against the current URL; **same host** → re-run `assertPublicHost` on it and
  continue the loop (each hop re-validated); **different host** → throw
  `crossHostRedirect(from:to:)` exactly as today; missing/invalid `Location`
  → `httpFailure(status)`. Observable behavior is unchanged (same-host
  redirects work, cross-host reported) — but no request is ever *sent* to an
  unvalidated destination.

**Test** (`Tests/ToolKitWebTests/FetchURLToolTests.swift`, extend the existing
stub-`URLProtocol` pattern): a 302 to another host throws `crossHostRedirect`
*and the stub records no request to the second host*; a 302 to the same host
succeeds and records `assertPublicHost` called twice (inject a counting
`assertPublicHost` closure).

## 2. `fetch_url`: cap the body while streaming, not after

Same file, same rewrite: with `session.bytes` in hand, accumulate into `Data`
and `throw FetchURLError.responseTooLarge` the moment the count exceeds
`maximumResponseBytes` — never buffer past the cap. **Test**: a stubbed
response streaming > cap throws without materializing the full body (assert
via a response larger than cap by 10× and a peak-size check is overkill — just
assert the throw).

## 3. Journal: tolerate a torn tail

`Sources/Recorder/RunJournal.swift`, `events(for:)`. A crash mid-append leaves
a partial final line; today that throws `corruptEntry` forever. Change: decode
line by line; **if the failing line is the last one, return the events decoded
so far** (the torn tail is the expected residue of a crash — exactly what the
journal exists to survive); a failing line that is *not* last still throws
`corruptEntry`. **Tests** (`RunJournalTests`): valid events + garbage tail
bytes (no trailing newline) → events returned, no throw; garbage line in the
middle → throws with the right line number.

## 4. `InstrumentedTool`: the registration write must not be `try?`

`Sources/Recorder/InstrumentedTool.swift`. The `toolRegistered` append is the
registered-before-execute guarantee; propagate its failure (`try await`, no
`?`) so a tool never executes unrecorded — add
`ToolInstrumentationError.journalUnavailable` wrapping the underlying error.
The `toolStarted` append stays best-effort (`try?`). The `toolCompleted`
appends stay best-effort **deliberately** — a post-effect write failure must
not destroy a successful result, and registered-without-outcome already reads
as "unknown, ask" on the next resume, which is the guard working; put that
reasoning in a comment. **Test** (`InstrumentedToolTests`): a journal whose
`append` throws on `toolRegistered` → the base tool is *never called* and the
error surfaces; a journal that throws only on `toolCompleted` → the output is
still returned.

## 5. Anthropic: map `ReasoningLevel`, stop hard-coding max effort

`Sources/Executors/AnthropicExecutor.swift`. Today every request sends
`"thinking": ["type": "adaptive"]` + `"output_config": ["effort": "max"]`.
First inspect the actual enum (`grep -A6 'enum ReasoningLevel'` in the
FoundationModels swiftinterface — Xcode 27 beta 3 path is in
docs/research/foundation-models-adaptation.md); then map
`request.contextOptions.reasoningLevel`: low/medium/high → `"output_config":
["effort": <level>]` with adaptive thinking; unspecified/default → adaptive
thinking, **no** `output_config` key (provider default); a custom case maps
through if expressible, else nearest named level. Keep `"thinking":
["type": "adaptive"]` in all cases (the shape live verification proved).
**Test** (`StreamParsingTests` file or a new `ExecutorRequestTests`): encode
requests at each level and assert the body's `output_config` presence/value —
the encoder is pure, no network needed.

## 6. Executors: a 200 non-SSE body must not become a silent empty reply

Both executor files + `StreamParsing.swift`. After `validate(response:)`,
check `Content-Type`: if it does not contain `text/event-stream`, drain up to
16 KB of the body and throw
`ProviderStreamError.event(provider:type:"non_sse_response", message:
<body prefix>)`. Belt-and-braces in the same loop: if the byte stream ends
having produced **zero** events, throw the same error with message "empty
stream". **Test**: stubbed 200 with `application/json` error body → typed
throw carrying the body text.

## 7. Error diagnostics: keep the provider's error body

`AnthropicExecutor.swift` (`ExecutorRequestEncoding.validate`): on non-2xx,
drain up to 16 KB from the bytes stream and include the prefix:
`httpFailure(provider:status:message:)` (extend the error case; update its
`errorDescription`). Callers pass the bytes sequence in. **Test**: stubbed 429
with a JSON body → error description contains the body text.

## 8. Small items, same PR

- `CheckpointStore.loadAll`: keep skipping corrupt files (a resume list must
  not be blocked by one bad checkpoint) but say so in a doc comment, and add
  the test proving a corrupt file alongside a good one yields the good one.
- `NetworkSafety.resolve`: move the blocking `getaddrinfo` off the cooperative
  pool — wrap in `withCheckedThrowingContinuation` dispatched to
  `DispatchQueue.global()`. Behavior identical; add no new test (covered by
  existing NetworkSafetyTests).
- DNS-rebinding TOCTOU: not fixable at this layer without a custom connection;
  add one sentence to `FetchURLTool.description` and a code comment naming the
  accepted limitation.

## Verification and DOD

- `swift test` green on macOS; `xcodebuild -scheme WorkKit-Package -destination
  'generic/platform=iOS' build` green.
- New tests exist for items 1–7 (item 8: checkpoint test only).
- ENGINEERING.md: fetch_url's redirect/cap behavior and the journal's
  torn-tail tolerance updated in the tool/Recorder sections; nothing else
  changes reality.
- ROADMAP: delete item 1 (this errata item), renumber.
- Delete this plan (absorption rule).

Out of scope: everything else — no Recorder features, no executor options
surface, no new tools. This increment only makes existing claims true.
