# Foundation Models adaptation POC

An isolated macOS 27 conformance harness. It does not belong to the production app
target and does not change the runtime decision in ADR-0006.

## Reproducible offline gate

From the repository root:

```sh
swift test --package-path Experiments/FoundationModelsPOC
swift run --package-path Experiments/FoundationModelsPOC foundation-models-probe all
```

The first command runs 12 Swift Testing cases. The second replays representative,
credential-free provider stream fixtures and prints a structural pass/fail matrix.
Run one fixture case with `deepseek`, `google`, or `anthropic` instead of `all`.

The fixtures preserve the structural fields needed by the POC but are reconstructed
from verified provider wire shapes; they are **not raw captures of the earlier live
requests**. No fixture contains an API key or user data.

## Apple executor/session runtime gate

The separate executable contains a real `LanguageModel`, `LanguageModelExecutor`,
`LanguageModelSession`, and `FoundationModels.Tool` two-request tool cycle:

```sh
swift run --package-path Experiments/FoundationModelsPOC \
  foundation-models-session-probe \
  --fixture-root Experiments/FoundationModelsPOC/Tests/FoundationModelsPOCTests/Fixtures
```

It is separate from the offline target because the current machine cannot load it.
On macOS 27 build `26A5378n` with FoundationModels framework build `26A5377s`, the
binary exits at dynamic linking with a missing
`LanguageModelExecutorGenerationChannel.send` symbol. Xcode 27 build `27A5194q` and
its SDK stub do export that symbol. This is a measured SDK/runtime seed mismatch.

Re-run this command after installing a matching macOS seed. A successful result will
report two model requests, one bridged tool call/output, reasoning and signature
entries, canonical transcript archive replay, and usage.

## Credentials and live providers

Neither offline command reads credentials. Reproduce one direct two-request provider
cycle with:

```sh
Experiments/FoundationModelsPOC/Scripts/live-provider-probe.sh deepseek
Experiments/FoundationModelsPOC/Scripts/live-provider-probe.sh google
Experiments/FoundationModelsPOC/Scripts/live-provider-probe.sh anthropic
```

The script finds the repository-root `.env` in the current or primary worktree, reads
`DEEPSEEK_API_KEY`, `GOOGLE_API_KEY`, or `ANTHROPIC_API_KEY`, and prints only structural
booleans and HTTP statuses. It never prints or persists a credential. Anthropic's
current `claude-sonnet-5` API uses adaptive thinking with maximum effort; the older
`thinking.type: enabled` request is now rejected.

These direct calls do not pass through Apple's executor/session API and therefore are
supporting transport evidence rather than a passing Apple architecture gate.
