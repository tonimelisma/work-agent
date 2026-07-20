# Plan: carve the app out; make this an SPM-root repo

**Roadmap item 1.** Toni, 2026-07-19: "the app is moving out of this repo… create a
plan to carve the app out of this repo for good. can you change the build targets
etc and make this an SPM repo?" Answer: yes — every step below is mechanical; the
only thing an agent cannot do alone is create the destination GitHub repo under
Toni's account (step 1). Everything is verified against the current tree: app code
in `Work Agent/` + `Work AgentTests/` + `Work Agent.xcodeproj`, package in
`AgentKit/` with its own `Package.swift`, app→package the only dependency direction
(ENGINEERING.md), app docs parked in `docs/app/APP.md`.

## Order of operations

Do the app's exit **before** the SPM-root restructure — moving `Package.swift` to
the repo root while the Xcode project still references the package by path would
break the app build mid-flight.

### 1. Destination repo (Toni, or agent with `gh` + his say-so)

`gh repo create tonimelisma/work-agent-app --private` (name Toni's call). Nothing
else blocks on a human.

### 2. Move the app (agent, new repo)

- Copy `Work Agent/`, `Work AgentTests/`, `Work Agent.xcodeproj/`, and
  `docs/app/APP.md` (→ `docs/APP.md`) to the new repo. Plain copy, not
  `git filter-repo`: this repo keeps the full history (the research and docs here
  reference it), and the app repo starts clean with one import commit noting the
  source SHA.
- `.env` is **not** copied (it's gitignored here and stays wherever tests need it);
  the new repo gets its own `.gitignore` (same secrets/Xcode rules) and a short
  user-first README per plans/package-readme.md's app-README genre: what the app
  is, screenshot, requirements, "built on AgentKit" developer section.
- MIT LICENSE, copied.

### 3. Repoint the app's package dependency (agent, new repo)

In `Work Agent.xcodeproj`, replace the local-path package reference to `AgentKit`
with a remote reference to this repo's URL, `branch: "main"` until the first tag.
Live-smoke tests (`LiveSmokeTests`) move with the app for now — they exercise
executors through app-side keys; the package keeps its own gated live tests when
the `.env` plumbing is ported (backlog item there, not a blocker).
Verify: `xcodebuild -scheme "Work Agent" build test` against the remote reference.

### 4. Strip this repo to the SPM (agent, this repo, single PR)

- `git rm -r "Work Agent" "Work AgentTests" "Work Agent.xcodeproj" docs/app`.
- Move the package to root: `git mv AgentKit/Package.swift Package.swift`,
  `git mv AgentKit/Package.resolved Package.resolved`,
  `git mv AgentKit/Sources Sources`, `git mv AgentKit/Tests Tests`; delete the
  empty `AgentKit/` folder (verified 2026-07-19: those four entries are the
  folder's entire contents). The `AGENTS.md → CLAUDE.md` symlink stays. Root
  `Package.swift` is what SwiftPM requires for remote consumption — this *is*
  the "make this an SPM repo" step.
- Scrub: README's app mentions (two-line reference-apps section now links the new
  repo), ENGINEERING.md's app sections (move nothing — they're already summarized
  in APP.md which left; delete the app halves here), CLAUDE.md's "app still lives
  here" sentence, any `docs/` link into the deleted trees. `rg -i "work agent/|xcodeproj|docs/app"`
  must come back empty.
- CI (add now that it's cheap): GitHub Actions running
  `swift build && swift test` on macOS 27 runners for both
  `-destination` platforms. No app scheme left to build.

### 5. Verify the seam end to end

- This repo: `swift test` green from a clean clone, macOS and iOS destinations.
- App repo: builds and tests against this repo's `main` by URL — the first real
  proof the package works as an external dependency, worth recording in
  ENGINEERING.md here.
- Both repos' docs: no reference into the other's tree except by URL.

## Deliberately not in this plan

Renaming the repo or the package (the name decision is roadmap item 7,
publication); tagging a version (gated on OS 27 GA); splitting ToolKit or the
executors into separate packages (only on demonstrated divergence).
