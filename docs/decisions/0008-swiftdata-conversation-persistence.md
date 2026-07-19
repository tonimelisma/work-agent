# ADR-0008 — App conversation persistence: SwiftData

- **Status:** Accepted
- **Date:** 2026-07-19
- **Deciders:** Toni (via increment-4 DOR: "the package exposes protocols and does not
  decide this app choice" — agent-loop-implementation.md §10 open question 3)

## Context

Increment 4 needs concrete storage for the app's side of a durable conversation: the
`ConversationRecord`s the sidebar lists (FR-071), each one's `[ChatMessage]` display
history, and the last committed `TranscriptArchive` a run resumes from. AgentKit's
`RuntimeCore` deliberately stays out of this decision — it exposes `RunJournal` and
`CheckpointStore` as protocols and ships a file-backed implementation of each, but the
*app*-owned conversation list is explicitly the app's call (agent-loop-implementation.md
§2: "the app owns... the concrete task database and migration policy").

## Decision

**SwiftData.** One `@Model final class ConversationRecord` holding `id`, `title`,
`createdAt`/`updatedAt`, `messagesData: Data` (JSON-encoded `[ChatMessage]`, the UI
projection), `archiveData: Data?` (JSON-encoded `TranscriptArchive`, what a new turn
resumes from), and the FR-072 pause fields (`pausedRunIDValue`, `pausedExecutorID`). A
`@Query` in `ConversationListView` sorts by `updatedAt` for the sidebar; SwiftData's own
change tracking is what makes a background run's live text update in the UI without a
view model in between.

Messages and the archive are stored as encoded blobs, not a relational graph of message
rows. Nothing in this increment needs to query *inside* a conversation's messages —
the sidebar needs the conversation and its most recent line, the chat view needs the
whole list at once. A relational schema for that would be complexity paid for a query
pattern that doesn't exist yet (CLAUDE.md's no-premature-abstraction rule).

## Considered options

**SwiftData** *(chosen)* — Native, zero bundled dependencies (matches the project's
Swift-native bias), integrates with `@Query`/Observation with no bridging code, and is
Apple's forward-looking persistence story for exactly this shape of app. Cost: less
control over migration mechanics than a hand-rolled schema, and it's a newer framework
with less operational history than SQLite.

**Plain Codable files** (the increment-2 pattern this replaces — one JSON file for the
single conversation) — Simplest possible thing, and what increment 2 shipped. Rejected
now: it doesn't scale to *listing* many conversations without hand-rolling an index, and
increment 4 needs exactly that list (FR-071).

**SQLite / GRDB** — Battle-tested, full query power, most control. Rejected as more
mechanism than this increment's access pattern needs (see above), and it's a bundled
dependency the project doesn't otherwise carry (ADR-0002 keeps dependencies to demand).
Revisit only if a real need for relational queries over message content shows up.

## Consequences

**Good.** The sidebar is a two-line `@Query`; a background run mutating `record.messages`
updates any view showing that record automatically, which is what let increment 4 keep
runs alive across sidebar-selection changes (FR-071) without a hand-rolled observation
bridge.

**Bad.** `messagesData`/`archiveData` being opaque blobs means SwiftData can't index or
filter on message content — acceptable today, a real constraint if a later increment
wants to search across messages.

**Known gap.** No migration story is exercised yet — there is exactly one schema
version. The first time a field changes shape, SwiftData's migration mechanics get
their first real test.
