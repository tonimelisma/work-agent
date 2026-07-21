import Foundation
import FoundationModels
import Recorder

// REQ: agent-loop-implementation.md §3 — preserve Apple's intelligence-session types.
// This is the one place the app constructs a `LanguageModelSession`; it does not
// wrap `Transcript`, `Tool`, or `GenerationSchema` in a lookalike.

/// What one attempt against one executor produced.
struct RunAttemptResult: Sendable {
    var archive: TranscriptArchive
    init(archive: TranscriptArchive) {
        self.archive = archive
    }
}

/// Runs one full model/tool/model cycle against `model`, resuming from `archive` when
/// given. Apple's `LanguageModelSession` resolves any tool round-trips internally;
/// one attempt here is one `respond`/`streamResponse` call, not a manual turn loop.
func runSessionAttempt<Model: LanguageModel>(
    model: Model,
    tools: [any Tool],
    instructions: String,
    resuming archive: TranscriptArchive?,
    prompt: String,
    onDelta: (@Sendable (String) -> Void)? = nil
) async throws -> RunAttemptResult {
    let session: LanguageModelSession
    if let archive {
        session = LanguageModelSession(model: model, tools: tools, transcript: archive.transcript)
    } else {
        session = LanguageModelSession(
            model: model,
            tools: tools,
            instructions: Instructions(instructions)
        )
    }

    if let onDelta {
        var last = ""
        for try await snapshot in session.streamResponse(to: prompt) {
            if snapshot.content.count > last.count {
                onDelta(String(snapshot.content.dropFirst(last.count)))
            }
            last = snapshot.content
        }
    } else {
        _ = try await session.respond(to: prompt)
    }

    return RunAttemptResult(archive: TranscriptArchive(transcript: session.transcript))
}
