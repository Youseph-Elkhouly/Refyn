# Refine — Project Memory

Working memory for anyone (human or AI agent) picking up this project. It records what exists, why it is
built this way, what was verified, the gotchas, and what is left. Keep it current: update it when you change
behavior, add a milestone, or discover a pitfall. Last updated: 2026-11-05.

---

## 1. What Refine is

A native macOS app that lives in the MacBook notch and helps developers working with AI coding agents
(Claude Code, Codex, Cursor, T3 Code, Zed):

1. **Prompt engineering** — turns a rough instruction into a structured, context-aware prompt.
2. **Codebase understanding** — builds an evidence-backed graph of the real repository by static analysis.
3. **Living architecture** — after the user verifies an agent's changes, updates the graph and its Giotto diagram,
   so the next prompt has better context.

Tagline: **Better prompts. Deeper context. Living architecture.**

The full original product brief (sections 1–19, milestones 1–8) was supplied by the user in the first build
session. Its hard rules are listed in §4.

## 2. Repository and environment

- GitHub: https://github.com/Youseph-Elkhouly/Refyn (remote `origin`, branch `main`). The repo is named "Refyn";
  the product and code are named "Refine".
- Local path: `/Users/youseph.e/Desktop/PROMPTBUILDER`.
- History: `62e57c6 Starting point` (the user's initial scaffold: Package.swift, a single-file main.swift prototype,
  PromptPlan.swift, WorkspaceStore.swift, one test file), then `0196e8b Build Refine…` (the full implementation).
- Dev machine verified on: macOS 15 (Darwin 24.6), Xcode 16.0 (16A242d), Swift 6.0, Node v25.9.0, npm 11.12,
  git 2.39. The display has a notch: screen 1470×956 pt, `safeAreaInsets.top = 32`.
- Package tools version 6.0 → **Swift 6 language mode with strict concurrency** in every target.

## 3. How to build, run, test

```sh
Scripts/build-app.sh [release|debug]       # npm ci + tsc for the helper, swift build, assemble .build/Refine.app, ad-hoc codesign
open .build/Refine.app
(cd RefineHelper && npm ci && npm test)    # helper: tsc + node --test dist/test/*.test.js  (7 tests)
swift build && swift test                  # 25 tests (3 integration tests need Node + built helper; otherwise they XCTSkip)
.build/debug/Refine --snapshot <dir>       # renders collapsed/compose/result/custom states to PNG, then exits
osascript -e 'quit app "Refine"'           # quit the running app before rebuilding/relaunching
```

- Run from the `.app` for dictation: the bundle's Info.plist carries `NSMicrophoneUsageDescription`. Unbundled
  `.build/debug/Refine` works for everything else.
- `REFINE_SUPPORT_DIR` overrides `~/Library/Application Support/Refine` (used by the integration tests).
- `REFINE_HELPER_DIR` points the app at a helper checkout (the folder containing `dist/src/main.js`).

## 4. Non-negotiable product rules (from the brief)

- Never modify the user's repository. Never execute repository code during analysis.
- Never send whole repositories or files to the LLM; only a bounded retrieved context.
- Never label an inferred relationship as confirmed. Every confirmed element must be traceable to source evidence.
- A planned/proposed component must never appear as existing until it is implemented **and** verified.
- Agent output is supporting context, never proof; the repository state is the source of truth.
- Do not assume all repository changes were made by the agent (hence hand-off baselines).
- Never fabricate agent completion events; only implement integrations that have documented interfaces.
- Never record audio without explicit user action; never auto-send dictation to an external model.
- No private chain-of-thought requests in generated prompts; ask for brief, observable plans instead.
- API keys only in the Keychain. Removing a workspace never deletes the project folder.
- No Electron; WKWebView only where needed (the diagram canvas).
- Refine must not autonomously run shell commands or loop agent sessions (prompts *instruct* agents to loop).

## 5. Architecture overview

```
Sources/RefineCore/   (Foundation-only library; everything testable lives here)
  PromptPlan.swift                    PromptMode, TaskType, PromptTechnique (17), PlanTask, CodeReference,
                                      PlannedComponent, IntentValidation, PromptPlan
  WorkspaceStore.swift                class WorkspaceStore (GRDB DatabaseQueue, async read/write) — all persistence
  Models/CodebaseGraph.swift          Verification, ComponentType, SourceRef, GraphNode/Edge/Metadata,
                                      CodebaseGraph, ArchitectureDiff.between(old,new), ArchitectureSnapshot
  Models/Workspace.swift              Workspace (+ security-scoped bookmark), Note, SavedPrompt, ExecutionRecord
                                      (+ Baseline), FileChange, ChangeReview
  PromptEngineering/RequestAnalysis   deterministic intent, task type, constraints, key terms, complexity; TranscriptCleaner
  PromptEngineering/TechniqueRegistry mode + analysis → techniques (canonical order)
  PromptEngineering/LLMProvider       ModelPlan (model output schema + validated(knownPaths:)), OptimizationRequest,
                                      LLMError, protocol LLMProvider, GeminiProvider (REST, responseSchema)
  PromptEngineering/PromptComposer    deterministic prompt text from plan + techniques; chain(); topologicalOrder()
  PromptEngineering/PromptOptimizer   the 10-stage pipeline; cacheKey(for:)
  Workspace/WorkspaceContext.swift    RetrievedContext, ContextRetriever, WorkspaceDocument (workspace.md)
  Workspace/AppPaths.swift            support dir, per-workspace dir, speech model dir
  Architecture/HelperClient.swift     actor: spawn Node helper, JSON-lines protocol, timeouts, idle stop, locate node/script
  Architecture/ArchitectureService    actor: analyze, scan, beginExecution, review, confirm, reject, render, regenerateContext
  Agents/AgentAdapter.swift           AgentCapabilities, AgentAdapter, ManualAgentAdapter, AgentRegistry
  Security/Keychain.swift             generic-password wrapper

Sources/Refine/       (the app; SwiftUI + AppKit; @MainActor)
  main.swift                          manual NSApplication bootstrap (accessory policy) + `--snapshot` mode
  App/AppDelegate.swift               wiring: model, panel, status item, hotkeys, Settings/Architecture windows, AppActions
  App/PanelController.swift           NotchPanel (NSPanel, canBecomeKey) placement, expand/collapse, focus restore
  App/HotKeyCenter.swift              Carbon RegisterEventHotKey; press + release (push-to-talk)
  App/Shortcut.swift                  keyCode + Carbon modifiers, display string, UserDefaults storage
  App/Snapshots.swift                 ImageRenderer PNGs of panel states (dev tool)
  ViewModels/AppModel.swift           @Observable central state + all user flows
  ViewModels/VoiceController.swift    recording/transcribing state machine, waveform levels, model download
  ViewModels/Preferences.swift        UserDefaults-backed settings, VoiceMode
  Services/Audio/AudioRecorder        AVAudioEngine tap → 16 kHz mono Float via AVAudioConverter, RMS levels
  Services/Transcription/SpeechTranscriber  actor wrapping WhisperKit 0.14.1 (download, load, transcribe)
  Views/Theme.swift                   colors, IconButton, PillButtonStyle, Chip, SearchField, Waveform
  Views/Notch/                        NotchRootView (+ CollapsedPill), ExpandedPanelView (+ header, BannerView, WorkspaceMenu)
  Views/Prompts/                      ComposerView, ResultView (+ PlanDetails)
  Views/Workspaces/NotesView.swift    NotesView, NoteEditor (debounced autosave), SavedPromptsView, SavedPromptEditor
  Views/Architecture/                 ArchitectureView (+ ArchitectureViewModel), DiagramWebView, ReviewView
  Views/Settings/SettingsView.swift   Model / Shortcuts / Voice / Analysis tabs, ShortcutRecorder

RefineHelper/         (Node ≥20, TypeScript → dist/, ESM)
  src/main.ts                         stdin line loop, dispatch, exits when stdin closes AND pending requests finish
  src/protocol/messages.ts            PROTOCOL_VERSION=1, request parsing/validation, HelperError codes
  src/analysis/walk.ts                file discovery (git ls-files or crawl), exclusions, size limit
  src/analysis/languages.ts           extension → language; SUPPORT levels
  src/analysis/extract-ts.ts          TypeScript compiler API (parse only)
  src/analysis/extract-patterns.ts    Python, Swift, Prisma line-pattern extractors
  src/analysis/manifests.ts           package.json / tsconfig paths / requirements / pyproject / Package.swift
  src/analysis/graph.ts               facts → CodebaseGraph (modules, edges, resolution, classification)
  src/analysis/analyze.ts             incremental orchestration, fingerprints, hashes, git info
  src/git/git.ts                      read-only git helpers
  src/giotto/diagram.ts               CodebaseGraph → Giotto doc → SVG; REFINE_STYLE
  test/helper.test.ts, test/fixtures/sample-app/   fixture: Express + React + pg + FastAPI/SQLAlchemy + a fake .env

SharedSchemas/        helper-protocol.schema.json, codebase-graph.schema.json (documentation-grade JSON Schemas)
Scripts/build-app.sh  app bundle assembly
```

Project layout note: the brief suggested `RefineApp/…` folders with an Xcode project; we kept **SwiftPM**
(`Sources/Refine`, `Sources/RefineCore`) to match the user's starting scaffold and allow command-line builds. The
`.app` is assembled by `Scripts/build-app.sh`.

## 6. Key design decisions (and why)

### Persistence (GRDB/SQLite)
- One DB: `~/Library/Application Support/Refine/refine.sqlite`. Migrations:
  - `create-workspaces-and-prompts` — kept **byte-for-byte compatible** with the user's original scaffold so any DB
    created by the prototype still migrates.
  - `v2-notes-plans-architecture-executions` — adds `savedPrompts.updatedAt/planID`, tables `notes`,
    `promptPlans` (JSON blob + `cacheKey`), `architectureSnapshots` (JSON blob, `version` unique per workspace,
    `verified`), `executionRecords` (JSON blob). Copies the old single `workspaces.notes` column into a "Notes" note.
- Complex objects are stored as JSON blobs (dates as secondsSince1970). Note: Date round-trips lose sub-ms precision,
  so tests compare dates with accuracy instead of `==` on whole plans.
- Foreign keys are on; deleting a workspace cascades to all its rows and also deletes
  `Application Support/Refine/Workspaces/<id>/` (Refine's own metadata only).

### Prompt pipeline (PromptOptimizer.optimize)
1–4 are local and deterministic: `RequestAnalysis` → `ContextRetriever.retrieve` (top ≤6 components by token
overlap; notes with `includeInContext` up to 1,500 chars; ≤3 recent verified changes) → `TechniqueRegistry.select`.
5–7: **one** Gemini call (`gemini-2.5-flash`, temperature 0.2, `responseMimeType: application/json`,
`responseSchema`, `thinkingBudget: 0`, header `x-goog-api-key`). Then `ModelPlan.validated(knownPaths:)` checks
non-empty intent/objective, ≤25 items per list, unique task ids, known dependencies, no cycles, and **drops code
references whose paths the analyzer never saw** (with a notice).
8: `PromptComposer.compose` builds the text locally from the plan, so formatting is stable.
9: intent preservation. Key terms from the request (backticked, quoted, file names, camelCase, PascalCase,
snake_case, routes, numbers with units) must appear in the result; otherwise "## Original request (verbatim)" is
appended and `validation.repaired = true`.
10: the plan is saved. `cacheKey` = SHA-256(text, mode, custom techniques, context hash, iteration limit, provider
id, "v1"); the app reuses a cached **model-built** plan for identical inputs.
- Failure policy: offline, rate-limited, unavailable, invalid response, or failed validation → local plan plus a
  notice. **Invalid API key is rethrown** so the user sees it.
- Confirmed requirements (stated by the user) and suggested decisions (from the model) are kept separate in both
  the plan and the prompt.
- The system instruction marks `<workspace_context>` as untrusted reference data (prompt-injection defense).
- Auto mode thresholds (complexity 0–10): <2 zero-shot (+context, +constraints); 2–4 structured set; ≥5 advanced
  set; ≥8 adds chaining. Bugfixes with complexity ≥2 get a bounded loop.
- Task classification: a request is `.test` only if a test phrase is in its **first 4 words** (so "…and add tests"
  stays a feature). The order otherwise is bugfix, performance, refactor, ui, docs, config, investigation, feature.

### Codebase analysis (RefineHelper)
- File discovery: in a git repo `git ls-files -co --exclude-standard` (respects .gitignore); otherwise a crawl that
  skips ignored dirs and never follows symlinks.
- Always excluded: `.env*`, `.npmrc`, `.netrc`, `id_*` keys, `*credentials*`, `secret(s).{json,yaml,toml}`, cert/key
  extensions, tfstate, dependency/build dirs (node_modules, dist, build, .build, .next, venv, Pods, target, …),
  lockfiles, minified/map/generated files, binaries, files >512 KB, and a 20,000-file cap.
- Every scanned file is **hashed** (needed for change review). Only TS/JS (TypeScript compiler, `syntax`),
  Python/Swift/Prisma (`pattern`) are parsed; other languages are counted only. Non-code files use language
  `"Other"` and are filtered out of the graph and language stats.
- File index (`Workspaces/<id>/file-index.json`) is owned by the app and passed to the helper by path
  (`indexPath`). It is written atomically (tmp + rename). Rescans skip unchanged size+mtime, and skip re-parsing
  unchanged SHA-256.
- Modules = directories, collapsed by depth until ≤60; SwiftPM targets are never merged.
- Edges:
  - `imports` confirmed: relative TS/JS (with `.js`→`.ts`, `/index`), tsconfig `paths` aliases, monorepo package
    names, Python relative/absolute (tries `.`, `src`, the file's dir), Swift `import <LocalTarget>` (anchored to
    the shallowest module of that target).
  - `uses-database` / `depends-on` confirmed to `ext:<pkg>` for known DB packages (pg, prisma, mongoose, GRDB,
    sqlalchemy, …) and notable services (stripe, openai, WhisperKit, …).
  - `depends-on` **inferred**: Swift capitalized identifiers that match a type declared (uniquely) in another
    module; dropped when a confirmed import edge already links the pair.
  - `calls-api` **inferred**: fetch/axios/requests literal paths matched to defined routes (`:id`, `[id]`, `{id}`,
    `<id>` params, template-literal heads).
  - Unresolvable local imports become a warning with samples.
- Routes: Express-style `app|router|server.get('/…')`, Next.js app router `route.ts` exported handlers, Next pages
  API, FastAPI/Flask decorators, Vapor `app.get("…")`. Models: Prisma, TypeORM `@Entity`, mongoose, sequelize,
  drizzle tables, SQLAlchemy/Django/SQLModel classes, GRDB records and `create(table:)`, Core Data, SwiftData.
- Component type priority: test (all files are tests) → api (has routes) → database (has models) → entry → frontend
  (JSX/SwiftUI/AppKit majority, or a frontend dir with tsx/vue/svelte) → service (dir name or *Service/*Client/*Store
  symbols) → library.
- Git safety: every call passes `-c core.fsmonitor=false -c diff.external= -c core.pager=cat --no-pager`,
  `--no-ext-diff --no-textconv` on diffs, `GIT_OPTIONAL_LOCKS=0`, `GIT_TERMINAL_PROMPT=0`. Patches are capped at
  12,000 chars per file, and at most 200 paths per diff request.

### Helper process (HelperClient actor)
- Started lazily; `hello` handshake checks protocol == 1 and Node major ≥ 20. Stops after 90 s idle, on app quit
  (`applicationShouldTerminate` → `.terminateLater`), and by itself when stdin closes.
- Stdout is split by a lock-protected `LineBuffer` on the reader thread, then each complete line is handed to the
  actor. This avoids out-of-order chunk processing from unordered Tasks.
- Per-request timeout (default 180 s, analyze 600 s). **Bug fixed:** a cancelled timeout task must `return`, not
  fall through. It used to call `fail()`, which stopped the helper after every successful request
  (CancellationError in tests). `fail` now only acts if the id is still pending.
- Node lookup: Settings override → /opt/homebrew/bin, /usr/local/bin, ~/.volta, fnm default, /usr/bin, newest
  ~/.nvm version. It deliberately does not spawn a login shell.
- Script lookup: `REFINE_HELPER_DIR` → `Bundle.main/Resources/RefineHelper/dist/src/main.js` → walk up ≤6 dirs
  from the executable (dev builds).

### Feedback loop
- **Copy** (ResultView / saved prompts) → `ArchitectureService.beginExecution`: incremental analyze, then
  `Baseline{head, fingerprint, fileHashes (every scanned file), dirtyPaths (git status), snapshotID (latest
  verified)}`, saved as status `sent`.
- **Review Changes** → re-analyze; changed = hash differences vs the baseline (added/modified/deleted); git diff
  against the **baseline commit** (untracked files use `--no-index /dev/null`). Files dirty at baseline are flagged
  `hadPriorChanges`. `ArchitectureDiff` vs the baseline snapshot graph; manifests and test files are listed.
  `headMoved` is noted. Status becomes `reviewing`.
- **Confirm** → status `confirmed`, a new **verified** snapshot (label = plan intent) with a diff vs the previous
  verified one, and `workspace.md` regenerated. **Reject** → status `rejected`; the observed graph is stored as an
  **unverified** snapshot labelled "Rejected: …"; the verified graph is unchanged.
- `scan()` creates a new verified snapshot only when the fingerprint changed (initial scan / manual re-analyze).
- Workspace scans happen only when a workspace is added/selected without a snapshot, or on explicit Re-analyze.
  There is no background polling.

### Diagram (Giotto)
- Giotto pinned: `github:nicoloboschi/giotto#3d5159acdce4ece8f0a1e4a40cb1a8b99fe2e233` (v0.1.0, MIT). We use
  `toSvg` and `layoutWarnings` from `giotto/render`. Elements carry `data-id`; groups lay out children; tones come
  from our `REFINE_STYLE` (dark overrides under `dark`).
- Layout: root row of groups in the order Frontend, Entry points, API, Services, Modules, Data, External, Tests,
  then "Removed" and "Planned (not implemented)". Columns switch to a grid after 7 items. Databases and data
  externals are drawn as cylinders.
- Inferred edges are dashed, unknown edges dotted, added edges green. Diff tones: added (green), modified (yellow),
  removed (red dashed ghost). Planned components are dashed purple with dotted arrows.
- At most 45 nodes are shown (changed nodes kept first, then by degree, then by file count); the rest are counted
  in the subtitle and in `hidden`.
- The canvas is a WKWebView with `loadHTMLString`, a non-persistent data store, a strict CSP (no network), and
  inline JS pan/zoom/select posting `data-id` to Swift. Navigation is blocked. The inspector is native SwiftUI.

### Notch panel
- `NotchPanel`: borderless + `.nonactivatingPanel`, level `.statusBar`, joins all spaces, `canBecomeKey = true`.
- Notched screen = the first screen with `safeAreaInsets.top > 0`. Notch width = screen width minus the
  `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` widths. Collapsed = notch width + 96 (150 while recording/
  transcribing) × notch height, flush to the top, flat top edge with rounded bottom corners. No notch → 170×30 pill
  just under the menu bar.
- Expanded = 660×560 (+ notch height; content is padded below the notch). Spring animation.
- Expanding remembers the frontmost app; collapsing via shortcut/Esc/chevron re-activates it. Auto-collapse
  happens when another app becomes active (setting: "Collapse when I switch to another app"). It is suppressed
  during NSOpenPanel via `withoutAutoCollapse`.
- Verified live: the collapsed panel is 275×32 at x=597 on the 1470-pt screen, centered on the notch.

### Shortcuts & voice
- Carbon `RegisterEventHotKey`: no Accessibility permission; key-down and key-up are delivered on the main thread
  (handled with `MainActor.assumeIsolated`). Defaults: toggle ⌃⌥Space, push-to-talk ⌃⌥D. They are recordable in
  Settings, and a non-shift modifier is required.
- **Bug fixed:** `kVK_F1...kVK_F12` is not an ascending range (F1=122, F12=111) and crashed `Shortcut.display`.
  It is now an explicit array.
- Voice modes: Transcribe (raw), Clean (local `TranscriptCleaner`: fillers, stutters, spacing), Optimize (clean,
  then `optimize(useModel: false)`, i.e. a local draft; nothing is sent to Gemini automatically).
- WhisperKit **0.14.1** (0.x avoids the 1.x Vapor/server dependency tree; builds with Xcode 16.0). Models
  `openai_whisper-{tiny,base,small}.en` are downloaded only from Settings › Voice into
  `Application Support/Refine/SpeechModels`. Loaded with `download: false`. Presses shorter than 0.35 s are ignored.

### Agents
- `AgentRegistry`: Claude Code, Codex, Cursor, T3 Code, Zed, Other — all `ManualAgentAdapter` with no
  capabilities. This is deliberate: no documented completion interface is wired yet, so none are faked. The
  selected agent is stored on the ExecutionRecord.

## 7. Verification status (what was actually run)

- `npm test` in RefineHelper: 7/7 pass (exclusions, sample-app graph incl. confirmed vs inferred edges and evidence,
  incremental reuse + change detection, Giotto render + planned overlay, route matching, protocol validation, the
  stdio process end-to-end).
- `swift test`: 25/25 pass. That is 16 prompt-engineering tests, 7 store/graph tests, and 3 integration tests that
  run the real Node helper against a git-initialized copy of the fixture: scan → unchanged rescan reuses → dirty
  baseline file not attributed → review → confirm v2 → workspace.md updated → render; reject keeps verified;
  helper restart.
- `Scripts/build-app.sh release` produces a 40 MB `.build/Refine.app`. It launches, creates the DB, and places the
  panel over the notch (checked via CGWindowList).
- UI checked via `--snapshot` PNGs (layout, header, buttons, notch band). **Limitation:** ImageRenderer draws
  AppKit-backed controls (TextEditor, Menu, segmented Picker, ScrollView) as yellow placeholders, and
  `screencapture` returned blank (the terminal lacks Screen Recording permission). So these were not verified by
  hand in the running UI: clicking through flows, real dictation (needs a mic grant + model download), a live
  Gemini call (no key configured), and the WKWebView diagram's interactivity.
- Release builds print "Looking for a function: …" lines from the Swift 6.0 optimizer. They are harmless.

## 8. Known gaps / next steps

- Hand-test in the running app: add a workspace, optimize with a real Gemini key, copy → edit repo → review →
  confirm, open Architecture, dictation end-to-end.
- Agent hooks behind `AgentAdapter` (for example Claude Code's documented hooks writing a completion event file);
  not implemented.
- Deeper Python/Swift analysis (tree-sitter or language servers); Go/Rust/Java support.
- Sandboxing: the app is ad-hoc signed and not sandboxed. Bookmarks are stored with `.withSecurityScope` for a
  future sandboxed build.
- Optional model-assisted interpretation of ambiguous architecture changes (the brief allows selective model use;
  currently all architecture reasoning is static).
- Prompt history browser (plans are persisted; the UI only shows the current plan and saved prompts).
- Notarization and a proper app icon.

## 9. Gotchas for future work

- Swift 6 strict concurrency: don't capture `[weak self]` vars into nested `Task`s in Process/pipe callbacks.
  Route through `nonisolated` helpers (`deliver`, `deliverExit`). Don't pass async closures to `Optional.map`.
- `Preferences.defaults` must be a computed property (a static `UserDefaults` stored property is a concurrency error).
- Memberwise inits of public structs are internal. Add explicit `public init` when the app target constructs
  them (this already bit `OptimizationRequest` and `RetrievedContext`).
- The helper's `tsconfig.json` includes only `src/**/*.ts` and `test/*.ts`; including the fixtures makes `tsc` fail
  on their imports.
- `npm test` runs `node --test dist/test/*.test.js` (a directory argument fails on Node 25).
- The fixture `RefineHelper/test/fixtures/sample-app/.env` is intentionally committed (fake value) to test
  secret exclusion.
- Auto mode classifies the deny-listed `rm` deletion as destructive. In earlier sessions, deleting files via
  shell was blocked, so obsolete files were overwritten rather than removed.
- When adding a DB migration, never edit existing migrations; append a new one.
- Repo-level AGENTS.md (in the user's home) asks to run `graphify update .` after code changes when
  `graphify-out/` exists; it does not exist in this repo.

## 10. User preferences observed

- Wants work to be pushed to GitHub (Refyn) as it progresses.
- Asked for a clear "done" message at the end of a build, followed by an updated, very detailed MEMORY.md
  committed into the repo.
- Switches models mid-session (Sonnet 5.5 → Opus 5.5); commit attribution follows the active model.
