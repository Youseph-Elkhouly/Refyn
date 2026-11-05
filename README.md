# Refine

**Better prompts. Deeper context. Private by default.**

Refine is a native macOS companion that lives in the MacBook notch. It turns rough instructions into effective prompts for coding agents and uses local workspace analysis, notes, and saved instructions to add relevant context.

```
open (⌃⌥Space) → pick workspace → type or dictate → Optimize → Copy → run in your agent
```

## Requirements

- macOS 14+, Xcode 16 / Swift 6
- Node.js 20+ (for the analysis helper)
- Git (optional, improves workspace file discovery)
- A Gemini API key (optional; without one, prompts are built by local rules)

## Build and run

```sh
Scripts/build-app.sh            # builds helper + app → .build/Refine.app (release)
open .build/Refine.app
```

Development:

```sh
(cd RefineHelper && npm ci && npm test)   # helper: build + 7 tests
swift build && swift test                  # app + core: 25 tests (integration tests need Node and the built helper)
.build/debug/Refine                        # run unbundled (dictation needs the .app for its microphone usage string)
.build/debug/Refine --snapshot /tmp/snaps  # render the panel's states to PNGs and exit
```

First run: the panel appears as a small pill around the notch (or at the top center on displays without one). Click it or press **⌃⌥Space**. Add a workspace from the workspace menu; Refine scans it once. Add your Gemini key in **Settings › Model**, and download a speech model in **Settings › Voice** to dictate (hold **⌃⌥D**).

## Architecture

```
Sources/
  RefineCore/                     Foundation-only library, fully unit-tested
    PromptPlan.swift              PromptPlan, techniques, modes (the "what the user wants" model)
    WorkspaceStore.swift          GRDB/SQLite persistence + migrations
    Models/                       Workspace, Note, SavedPrompt, CodebaseGraph
    PromptEngineering/            RequestAnalysis, TechniqueRegistry, LLMProvider (Gemini), PromptComposer, PromptOptimizer
    Workspace/                    context retrieval, workspace.md generation, app paths
    Architecture/                 HelperClient (process + protocol)
    Workspace/                    WorkspaceAnalyzer, context retrieval, workspace.md generation, app paths
    Agents/                       AgentAdapter interface + manual adapters
    Security/                     Keychain
  Refine/                         SwiftUI + AppKit app
    App/                          entry point, AppDelegate, notch PanelController, Carbon HotKeyCenter, snapshots
    ViewModels/                   AppModel, VoiceController, Preferences
    Services/                     AudioRecorder (AVAudioEngine), SpeechTranscriber (WhisperKit)
    Views/                        Notch, Prompts, Workspaces, Architecture, Settings
RefineHelper/                     Node.js helper (TypeScript)
  src/protocol/                   versioned JSON-lines protocol
  src/analysis/                   walker, extractors (TS compiler API; Python/Swift/Prisma patterns), graph builder
  src/git/                        read-only git (status, diff) with repo-config programs disabled
SharedSchemas/                    JSON Schemas for the protocol and CodebaseGraph
Tests/RefineCoreTests/            unit + integration tests
```

Responsibilities are separated as the spec asks:

| Part | Does | Never does |
| --- | --- | --- |
| Static analyzer (helper) | Files, languages, frameworks, imports, symbols, routes, models, entry points | Execute repository code, read secrets |
| Gemini 2.5 Flash | Intent, decomposition, constraints, criteria — as schema-validated JSON | See whole files; its paths are dropped unless the analyzer knows them |
| Workspace analyzer | Extracts bounded project metadata for relevant prompt context | Execute repository code or read secrets |

### Prompt pipeline

1. Intent extraction · 2. task classification · 3. context retrieval (top components by overlap and included notes; never whole files) · 4. technique selection (Auto/Basic/Advanced/Custom over 17 techniques) — all local and deterministic.
5–7. One Gemini call with `responseSchema` returns tasks + dependencies, constraints, success criteria, confirmed requirements vs. suggested decisions, missing information, planned components. It is validated: required fields, unique task ids, known dependencies, no cycles, bounded sizes; file references the analyzer cannot confirm are removed. Repository content is wrapped as untrusted reference data.
8. The prompt is composed locally and deterministically from the plan. 9. Intent preservation: identifiers, file names, routes, numbers and quoted strings from the request must survive; if not, the original request is quoted verbatim. 10. The plan (including the original prompt) is saved.

Offline, rate-limited or invalid model output falls back to a local plan with a visible notice. An invalid API key is reported, not silently replaced. Identical inputs reuse the cached plan (no second model call).

### Codebase graph

Nodes are modules (directories, collapsed to ≤60; SwiftPM targets kept separate) plus notable external data/service dependencies. Edges carry evidence (`file:line`) and a verification status:

- **confirmed** — resolved imports (relative, tsconfig aliases, monorepo packages, Python packages, SwiftPM targets) and imports of database packages.
- **inferred** — Swift type-name references across modules; client `fetch`/`axios` paths matched to defined routes. Drawn dashed; never labelled confirmed.
- Unresolvable local imports are reported as warnings.

Analysis depth is reported per language: TypeScript/JavaScript are parsed with the TypeScript compiler (syntax); Python, Swift and Prisma use pattern extraction; everything else is counted, not analyzed.

Excluded always: `.env*`, keys/certificates, credential and secret files, `node_modules`, build output, lockfiles, minified/generated files, binaries and files over 512 KB. In git repositories, `.gitignore` is respected.

Incremental: a per-workspace file index (in Application Support) lets rescans skip unchanged files by size+mtime, and skip re-parsing unchanged content by SHA-256.

### Workspace context

Workspace files are scanned locally. Refine retrieves relevant component metadata, project notes, and bounded source references for each prompt.

## Data and privacy

- Everything lives in `~/Library/Application Support/Refine/` (`refine.sqlite`, `Workspaces/<id>/workspace.md` and `file-index.json`, `SpeechModels/`).
- The Gemini key is stored in the Keychain.
- Refine never writes to your repository. Removing a workspace deletes only Refine's records.
- Dictation is recorded only while you hold the shortcut or after you click the mic, is transcribed on-device, and is never sent to a model automatically (the Optimize voice mode builds a local draft).

## Agent integrations

Agent destinations (Claude Code, Codex, Cursor, T3 Code, Zed, other) are labels for copy-and-paste hand-off. Refine does not monitor agent sessions.

## Known limitations

- Python/Swift analysis is pattern-based, not a full parser; Go, Rust, Java and others are not analyzed yet.
- The app is ad-hoc signed and not sandboxed (the helper reads the selected folders directly); security-scoped bookmarks are stored for a future sandboxed build.
- `--snapshot` cannot draw AppKit-backed controls (text editors, menus, segmented pickers), which appear as placeholders in the PNGs.

## Third-party

- [GRDB.swift](https://github.com/groue/GRDB.swift) (MIT) — SQLite.
- [WhisperKit](https://github.com/argmaxinc/WhisperKit) (MIT) — on-device speech recognition.
- [TypeScript](https://github.com/microsoft/TypeScript) (Apache-2.0) — parsing JS/TS (parser only).
