# Plan: iterations 1–2 review top-up

**Written:** 2026-07-22, after re-reviewing PRs #13–#15 against the renamed
`swift-workkit` tree and rerunning the live matrix with Xcode 27.

The earlier review's code findings were fixed by PR #15. This final pass found
three small pieces of errata and one changed external fact. No product decision
is open.

## Work

1. In `Sources/ToolKitWeb/NetworkSafety.swift`, replace the Xcode 27-deprecated
   `String(cString:)` conversion with an explicit decode of the bytes preceding
   the first null terminator. Preserve the resolver's behavior.
2. In `Tests/ExecutorsTests/OpenAIResponsesTests.swift`, remove the unnecessary
   `try` that Xcode 27 now diagnoses.
3. Correct `docs/engineering/ENGINEERING.md` from 110 to 131 discovered tests.
4. Record the 2026-07-22 live result everywhere it changes current truth:
   GLM now completes the full tool cycle, so the matrix is 10 of 11; remove its
   account action from `docs/product/ROADMAP.md`; update `README.md`,
   `docs/product/PRODUCT.md`, `docs/engineering/ENGINEERING.md`, and
   `docs/research/provider-chat-endpoints.md`. Thinking Machines remains the
   sole failure, returning HTTP 400 because `inkling` is unsupported on the
   account.

No new FR/NFR is minted: this changes no behavior or architecture and only
keeps the existing implementation warning-free and its verification record
truthful.

## Verification

- Clean the renamed repository's derived build products so no stale
  `/Development/Work Agent/` paths remain.
- `swift test`
- `xcodebuild -scheme WorkKit-Package -destination 'generic/platform=iOS' build`
- With `.env` sourced:
  `swift test --filter 'ExecutorsLiveTests|WebSearchLiveTests'`
- `git diff --check`

After the code increment merges, delete this consumed plan in the same PR.
