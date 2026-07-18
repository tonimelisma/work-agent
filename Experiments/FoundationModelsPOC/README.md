# Foundation Models adaptation POC

An isolated macOS 27 conformance harness. It does not belong to the production app
target; its results are the technical evidence behind the accepted ADR-0006 hybrid.

## Reproducible offline gate

From the repository root:

```sh
swift test --package-path Experiments/FoundationModelsPOC
swift run --package-path Experiments/FoundationModelsPOC foundation-models-probe all
```

The first command runs 20 Swift Testing cases. The second replays representative,
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

This gate passes on macOS 27 beta 3 v2 (`26A5378n`) with Xcode 27 beta 3
(`27A5218g`). It reports two model requests, one bridged tool call/output, reasoning
and signature entries, canonical transcript archive replay, and usage.

The earlier loader failure was caused by Xcode 27 beta 1 (`27A5194q`) being used with
the beta-3 OS. Beta 1 declared a generic `send<T: Event>(T)` ABI symbol while the
beta-3 runtime exports the concrete `send(Event)` symbol. Updating Xcode and rebuilding
against its beta-3 SDK fixed the incompatibility; no POC or provider workaround was
required.

The offline suite also measures the decision-critical session semantics with scripted
executors and tools. It proves provider- and tool-task cancellation propagation,
application-controlled atomic retry through `.revertTranscript`, concurrent tool
execution with source-order transcript commits, cross-provider reconstruction, and
usage snapshots. It also records two boundaries Work Agent must own: tool failures are
surfaced as terminal `ToolCallError` values rather than model-visible correction
output, and session response snapshots may coalesce individual executor events.

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

Those direct calls remain a transport-isolation diagnostic. The architecture gate now
also passes through the Swift executable's real Apple executor conformances. After
exporting the same `.env` values into the process environment, run:

```sh
swift run --package-path Experiments/FoundationModelsPOC \
  foundation-models-session-probe --live-provider deepseek \
  --fixture-root Experiments/FoundationModelsPOC/Tests/FoundationModelsPOCTests/Fixtures
# Replace deepseek with google or anthropic.

swift run --package-path Experiments/FoundationModelsPOC \
  foundation-models-session-probe --live-switch deepseek anthropic \
  --fixture-root Experiments/FoundationModelsPOC/Tests/FoundationModelsPOCTests/Fixtures
```

All three live provider/session cycles pass. The switch probe also passes: DeepSeek
completes the tool task, its foreign state is filtered from the replay archive, and
Anthropic continues the reconstructed session. No command prints a credential.
