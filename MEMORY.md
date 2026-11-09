# Refyn — Project Memory

Working memory for anyone (human or AI agent) picking up this project. It records what exists, why it is
built this way, what was verified, the gotchas, and what is left. Keep it current: update it when you change
behavior, add a milestone, or discover a pitfall. Last updated: 2026-11-05.

---

## 1. What Refyn is

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
  the product is branded Refyn; the existing RefineCore module name remains.
- Local path: `/Users/youseph.e/Desktop/PROMPTBUILDER`.
- History: `62e57c6 Starting point` (the user's initial scaffold: Package.swift, a single-file main.swift prototype,
  PromptPlan.swift, WorkspaceStore.swift, one test file), then `0196e8b Build Refine…` (the full implementation).
- Dev machine verified on: macOS 15 (Darwin 24.6), Xcode 16.0 (16A242d), Swift 6.0, Node v25.9.0, npm 11.12,
  git 2.39. The display has a notch: screen 1470×956 pt, `safeAreaInsets.top = 32`.
- Package tools version 6.0 → **Swift 6 language mode with strict concurrency** in every target.

## 3. How to build, run, test

```sh
Scripts/build-app.sh [release|debug]       # npm ci + tsc for the helper, swift build, assemble .build/Refyn.app, ad-hoc codesign
open .build/Refyn.app
(cd RefineHelper && npm ci && npm test)    # helper: tsc + node --test dist/test/*.test.js  (7 tests)
swift build && swift test                  # 25 tests (3 integration tests need Node + built helper; otherwise they XCTSkip)
.build/debug/Refyn --snapshot <dir>       # renders collapsed/compose/result/custom states to PNG, then exits
osascript -e 'quit app "Refyn"'           # quit the running app before rebuilding/relaunching
```

- Run from the `.app` for dictation: the bundle's Info.plist carries `NSMicrophoneUsageDescription`. Unbundled
  `.build/debug/Refyn` works for everything else.
- `REFINE_SUPPORT_DIR` overrides `~/Library/Application Support/Refyn` (used by the integration tests).
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

Sources/Refyn/       (the app; SwiftUI + AppKit; @MainActor)
  main.swift                          manual NSApplication bootstrap (accessory policy) + `--snapshot` mode
  App/AppDelegate.swift               wiring: model, panel, status item, hotkeys, Settings window, AppActions
  App/PanelController.swift           NotchPanel (NSPanel, canBecomeKey) placement, expand/collapse, focus restore
  App/HotKeyCenter.swift              Carbon RegisterEventHotKey; press + release (push-to-talk)
  App/Shortcut.swift                  keyCode + Carbon modifiers, display string, UserDefaults storage
  App/Snapshots.swift                 ImageRenderer PNGs of panel states (dev tool)
  ViewModels/AppModel.swift           @Observable central state + all user flows
  ViewModels/VoiceController.swift    recording/transcribing state machine, waveform levels, model download
  ViewModels/Preferences.swift        UserDefaults-backed settings, VoiceMode
  Services/Audio/AudioRecorder        AVAudioEngine tap → 16 kHz mono Float via AVAudioConverter, RMS levels
  Services/Transcription/SpeechTranscriber  actor wrapping WhisperKit 0.14.1 (download, load, transcribe)
  Views/Theme.swift                   monochrome design system: tokens (Theme.*, Space, Radius, Motion), RefynMark, RButton/RefynButtonStyle,
                                      IconButton, RTextField, REditor, SearchField, Segmented, RToggle, SectionHeader, SettingsGroup/Row,
                                      StatusIndicator, EmptyState, LoadingState, Chip, KeyHint, Waveform, .motion() (honors Reduce Motion)
  Views/Notch/                        NotchRootView (+ CollapsedPill), ExpandedPanelView (+ header, BannerView, WorkspaceMenu)
  Views/Prompts/                      ComposerView, ResultView (+ PlanDetails)
  Views/Workspaces/NotesView.swift    NotesView, NoteEditor (debounced autosave), SavedPromptsView, SavedPromptEditor
  Views/Review/ReviewView.swift       change review after a hand-off (the Architecture window/diagram UI was removed; do not reintroduce)
  Views/Settings/SettingsView.swift   Model / Shortcuts / Voice / Workspace tabs, ShortcutRecorder

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
(`Sources/Refyn`, `Sources/RefineCore`) to match the user's starting scaffold and allow command-line builds. The
`.app` is assembled by `Scripts/build-app.sh`.

## 6. Key design decisions (and why)

### Persistence (GRDB/SQLite)
- One DB: `~/Library/Application Support/Refyn/refine.sqlite`. Migrations:
  - `create-workspaces-and-prompts` — kept **byte-for-byte compatible** with the user's original scaffold so any DB
    created by the prototype still migrates.
  - `v2-notes-plans-architecture-executions` — adds `savedPrompts.updatedAt/planID`, tables `notes`,
    `promptPlans` (JSON blob + `cacheKey`), `architectureSnapshots` (JSON blob, `version` unique per workspace,
    `verified`), `executionRecords` (JSON blob). Copies the old single `workspaces.notes` column into a "Notes" note.
- Complex objects are stored as JSON blobs (dates as secondsSince1970). Note: Date round-trips lose sub-ms precision,
  so tests compare dates with accuracy instead of `==` on whole plans.
- Foreign keys are on; deleting a workspace cascades to all its rows and also deletes
  `Application Support/Refyn/Workspaces/<id>/` (Refine's own metadata only).

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
  `Application Support/Refyn/SpeechModels`. Loaded with `download: false`. Presses shorter than 0.35 s are ignored.

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
- `Scripts/build-app.sh release` produces a 40 MB `.build/Refyn.app`. It launches, creates the DB, and places the
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


## UI redesign (2026-11-05): strict monochrome

- Palette is grayscale only: bg #090909, surface #141414, input #1B1B1B, border #292929, hover #242424, text #FFF / #A1A1A1 / #666,
  primary button white on #090909. No accent, gradient, or semantic colors: state is conveyed by symbols, weight and text.
- All styling goes through `Theme` tokens and the components in `Views/Theme.swift`; do not hardcode colors/sizes in views.
- Notch: collapsed = black pill with the `RefynMark` + status dot; expanded = header (wordmark, workspace menu, notes/saved/settings),
  borderless editor ("What are you working on?"), controls (mic, mode segmented, ⌘↩ Optimize). Custom-mode techniques live in a popover to avoid layout jumps.
- Result view shows the original request above the optimized prompt; actions: Copy, Save, Regenerate (skips the plan cache), agent menu, review, new.
- Draft (`model.input`) is never cleared by navigation; only "New prompt" in the result view clears it. Info banners auto-dismiss after 4 s.
- Animations are short ease curves (no springs); `.motion()` and the panel frame animation respect Reduce Motion.
- `--snapshot` uses ImageRenderer, which cannot draw AppKit-backed views (TextEditor, ScrollView, Menu show as yellow placeholders), so use it for chrome/layout only.
- Removed: ArchitectureView, DiagramWebView, PillButtonStyle, SectionLabel, color tokens accent/success/warning/danger.


## Invention guard and model-output cleanup (2026-11-05)

- `RefineCore/PromptEngineering/ModelOutput.swift`: strips `<think>…</think>` (also a dangling `</think>` or an unclosed `<think>`) before JSON extraction; `LocalLLMProvider` uses `ModelOutput.jsonObject(from:)`.
- `RefineCore/PromptEngineering/InventionGuard.swift`: runs after schema/path validation. It checks numbers (including single digit), paths, symbols, URLs, quoted strings, and a maintained list of common libraries against the request, confirmed answers, and bounded workspace context. Unsupported actionable items are removed; demoted items become optional suggestions. Unknown path references are dropped by `ModelPlan.validated`.
- If a plan contains unsupported specifics, `PromptOptimizer` performs exactly one correction attempt. A second unsupported plan or malformed JSON uses the deterministic composer and adds a visible notice. Model load/runtime errors remain errors. Corrective instructions and the unanswered question list are data in `OptimizationRequest`, not hidden state.
- Tests: `Tests/RefineCoreTests/InventionGuardTests.swift`.

## Clarification flow and regression fix (2026-11-06)

- Root cause for verbatim results: Auto/Basic selected only `.zeroShot` for short prompts, and `PromptOptimizer` skipped its provider when techniques were limited to zero-shot/context/constraints. The local composer then returned the user's sentence unchanged, labeled “Local rules.” The clarification screen existed, but this path still allowed short task requests to be treated as direct rewrites when the question preference was off or answers were submitted.
- `PromptOptimizer` now forces underspecified requests and requests with answers/open questions through local inference. Auto/Basic use a structured output in that case; simple clear edits still stay deterministic. The composer includes user answers and unanswered questions even in Custom mode.
- The model receives unanswered checklist questions but is instructed not to emit a generic “Open questions” section or guess answers. The gap data remains internal for clarification and non-guessing behavior. Malformed model JSON falls back deterministically. The performance classifier recognizes ordinary “speed” phrasing; the test-scenario detector no longer treats the word “tests” alone as a list of scenarios.
- Evaluation: earlier pre-checklist run surfaced 0/8 expected gaps, kept 2/2 clear controls question-free, and averaged about 9.8 s across its 10 cases. Current eight-case underspecified run detected 8/8 expected gaps, had 0/8 unsupported concrete specifics survive, preserved request specifics in 8/8, and averaged 6.52 s. Both clear controls remained question-free (2/2). These are different runs/datasets, not a paired replay. The deterministic guard covers identifiers, paths, URLs, quoted text, common libraries and numbers; it does not prove that every unsupported natural-language suggestion is absent.
- Follow-up regression: the fixture for “add pagination to listUsers” now treats `pagination`/`paginate` as equivalent wording, while ungrounded URL success criteria are demoted to optional suggestions. Chained output retains a safe acceptance section even when all model criteria are rejected.
- When the user explicitly says to implement from notes, prompt generation now elevates the matching note's action items as user requirements. The checklist uses relevant notes to avoid asking questions those notes answer; unrelated notes do not satisfy checklist items. Added a real Qwen evaluation for the example note (older prompt history + completion notifications), which now produces a specific objective and both confirmed requirements.
- Composer UI now shrinks to a compact 300 pt panel when empty and grows to 380 pt once text is entered; clarification uses 400 pt while result/history retain the full panel. Editor placeholder contrast and global typography sizes increased. TextEditor keeps standard macOS ⌘C/⌘V behavior, and the prompt editor advertises those shortcuts.
- Verified: `swift build`; `swift test` (56 tests, 6 opt-in skips, 0 failures); live Qwen clarified-feature evaluation passed in 16.8 s; live Qwen referenced-note evaluation passed in 16.8 s and generated both requested items; latest eight-case Qwen clarification evaluation passed in 55.0 s (8/8 gaps, 0/8 unsupported specifics, 8/8 request-term preservation, 2/2 clear controls, 6.52 s mean latency); the corrected eight-case quality baseline passed in 87.4 s (all request markers retained, 4/4 structured cases have tasks and verification, 0 unverified references, clear rename stayed 23 characters and took <0.01 s). `Scripts/build-app.sh release` completed successfully and produced `.build/Refyn.app`.

## Local model speed (2026-11-06)
- Measured Qwen3-4B-4bit, 8-case baseline (REFINE_RUN_LOCAL_MODEL_EVALUATION=1 ... testPromptEngineeringBaselineEvaluation): one model call per request (no hidden retries), ~3s time-to-first-token for a ~3.5k-char prompt, decode ~33 tokens/s, 6–27s per complex request. Release build is not faster than debug: it is memory-bandwidth-bound.
- Shipped: `JSONObjectEndDetector` stops generation when the top-level JSON object closes; `LocalModelManager.warmUp()` loads an installed model at launch (shared `ensureLoaded()` so generate and warm-up never double-load).
- Tried and reverted: trimming the JSON schema (dropping missingInformation/plannedComponents/exampleReport/intentPreserved) and "omit empty keys". No measurable speed gain and the refactor case lost its tasks.
- Remaining levers, not done: prefix KV-cache reuse for the static instructions (~1–2s), shorter output (drop intent/role), a smaller fast model (Qwen3-1.7B) as an option, streaming progress in the UI.
- To run MLX tests in release: copy mlx.metallib into `.build/.../release/RefynPackageTests.xctest/Contents/MacOS/` and pass `-Xswiftc -enable-testing`.

## Playbooks: depth for vague requests (2026-11-06)
- Problem: output only restructured the user's words ("the animation for opening the notch is bad" came back as an objective plus generic sections).
- `Playbook.swift` (RefineCore) adds `PlaybookGuidance` (investigate / goodLooksLike / examples / avoid) for vague requests (complexity <= 4) on four topics: animation/motion, performance, visual design, bug. Deterministic, instant, works without the model, stack-specific lines only when the workspace stack is known.
- Product rule kept: this is general engineering knowledge shown in sections titled "suggested bar, not stated by the user"; it never enters `confirmedRequirements`. `PromptPlan.guidance` is optional so stored plans still decode. Cache key bumped to v3.
- A matched playbook forces the engineering path (no one-line direct rewrite), adds `.outputFormat`, and appends "first establish what is wrong" to the objective when no model objective exists.
- Not done: letting the model tailor the examples to the request (costs tokens/latency), more playbooks (API, data, auth, testing), user-editable playbooks.
- Playbooks are direction-aware (2026-11-06): the motion playbook reads the pace the user asked for (very slow / slow / fast / default) and moves its numbers with it (very slow = 800–1200 ms open, soft ease-in-out, responsive first frame), adds morph/content/fluidity bullets, strips "…fix this prompt:" prefaces from the objective, and titles the section "Target quality (derived from your request)". Reference example of a good optimized prompt came from the user (very slow, smooth notch open/close). Open item: the model path does not yet get this tailoring; the deterministic path does.

## Model prompt rewrite (2026-11-06)
- `OptimizationRequest.modelPrompt` rewritten: expert-prompt-engineer framing, explicit field semantics (confirmed/constraints = user words only; suggestedDecisions = useful direction with starting values; adaptive depth, no cap of three tasks), one task-type guidance paragraph, ONE compact few-shot example chosen by task type from `PromptExamples.swift` (vague, complex feature, bug, UI, constrained), brevity limits, "fix this prompt:" preface moved to `<user_background>`. JSON contract unchanged; maxTokens 1150 -> 1600. Kept test-required phrases ("do not return generic questions", "populate missingInformation", "Iteration limit:", "Example of the desired behavior").
- Simple requests now go through the model too (no direct rewrite) when a provider exists; if the model is not installed a simple request falls back to the old local cleanup with a notice. A result with only an objective is returned as a plain sentence.
- `InventionGuard` now separates values from facts: numbers/units in suggestions, tasks, criteria and verification are allowed (they are proposals); invented paths/identifiers/names/quoted labels are still flagged everywhere; requirements, constraints and the objective stay strict. Route detection no longer treats "UI/UX" or "open/close" as routes (this had caused false violations, a retry, and fallback to the deterministic builder).
- Acceptance criteria: kept when grounded, or when they add no new codebase fact and do not answer a skipped clarification question; otherwise demoted to suggestions. The model restating the whole request as a requirement or constraint is dropped.
- Playbooks no longer fire on creation requests ("add dark mode") and visual triggers are complaint words only.
- Measured with Qwen3-4B-4bit (testPromptQualityAcrossModes, testPromptEngineeringBaselineEvaluation): all samples parse and use the model with no fallbacks; typical call 17–30s versus about 13s before (longer prompt and richer output). The baseline "ambiguous" assertion was rewritten: "make authentication better" has no checklist gap, and the model is told not to fill missingInformation. Known 4B weaknesses: may still say "the app's prompt" for the "fix this prompt:" case, and some suggestions are generic.

## Speed: tiered routing, compact prompts, fast model (2026-11-06)
- Measured (M4, 16 GB, MLX): Qwen3-4B decodes 24–39 tok/s and reads ~280 tok/s; Qwen3-1.7B decodes ~75–85 tok/s and reads ~700 tok/s. Before this change the prompt was ~1,400 tokens, so prefill alone was 4.6–7 s on 4B.
- `OptimizationRouter` (no model call) picks a tier from `RequestAnalysis`, mode, open questions, answers, context: simple = local recipe/playbook, instant (`QuickRecipes`: rename, remove, small UI tweaks; `Playbook` complaints); moderate = compact prompt (~400–550 tokens, tiny one-shot example, no workspace block when empty), 700 output tokens, runs on the fast model when installed else 4B; complex (Advanced, long, many constraints) = full prompt (~1,100 tokens), 1,300 output tokens, 4B only. A short request with no recipe or playbook still goes to the model (moderate).
- Fast model = `mlx-community/Qwen3-1.7B-4bit` (~1 GB), optional download in Settings ("Fast model"). 1.7B dropped negative constraints ("4xx", "upload API") on complex requests, so it never handles complex. Both models loaded: ~2.9 GB peak, warm-up of both at launch. `LocalModelManager(modelID:)` per model; `Metrics` (prompt/output tokens, ttft, tok/s, load time) in `lastMetrics`.
- Benchmarks (`testBenchmarkRouted4BOnly`, `testBenchmarkRoutedWithFastModel`, REFINE_RUN_LOCAL_MODEL_EVALUATION=1): simple 0.01 s; moderate 4B-only 8.8–9.6 s, with 1.7B 3.8–4.6 s; complex 13–18 s (was 34–35 s). 8-case baseline total 101 s (was 184 s; original 90 s with weaker output).
- Reliability fixes: bare-string lists decode, empty/duplicate task ids and title-based dependencies are repaired (cycles still rejected), compact schema omits intent/taskType/role/unused keys, `codeReferences` only offered when workspace context exists (otherwise the model invented paths and triggered a retry plus fallback), retry only for complex and only for invented specifics (not dropped references), prompt-rule echoes ("do not invent files") filtered from results, whole-request constraint dropped when the model splits it.
- Remaining bottlenecks: complex requests are decode-bound on 4B (~330–420 output tokens at ~35 tok/s plus ~3.7 s prefill); prefix KV-cache reuse and streaming progress not done. Early stop and warm-up from the previous speed pass remain.

## Semantic fidelity and context relevance (2026-11-07)
- Root causes of the "image uploads" failures: (1) only invented *terms* were checked, so a model rewrite like "retry only on 5xx" or "show retry attempts in the progress UI" passed; (2) `ContextRetriever` matched components on any shared word, always sent the whole stack and every note, and the composer presented name-matched files as facts; (3) the user's own prohibitions and keep-unchanged clauses were filed under Requirements, so the Constraints section disappeared; (4) test scenarios were collapsed into one generic step with no rule for unstated outcomes.
- `SemanticValidator` (no model call, ~10 ms): reads the request as directives (prohibit / preserve / limit / test scenarios) with `clauses` + `parse`. `correct` removes generated items that contradict a prohibition, change or add behavior to a kept thing, narrow a prohibition into an "only" rule, state a status class the request never gave, conflict with a retry limit, or prescribe an outcome for a scenario the user only asked to test. It runs BEFORE `InventionGuard` so fixes never trigger a retry or fallback. `complete` moves rule-shaped requirements to Constraints, adds missing constraints/criteria (preserve, prohibit, retry arithmetic: N retries = N+1 attempts, failure-trigger criterion), writes one verification step per requested scenario (outcome stated -> test it; unstated -> run it and report observed behavior), adds a "Locate the code" task when no file is verified, and sets `plan.terminology` (shown as "Definitions that matter here": timeout vs HTTP error, 4xx/5xx, transient vs permanent, offline, authN vs authZ, latency vs throughput...).
- Context: a component needs an identifier hit, a distinctive word in its name/symbols, or two distinct matching words (words common to >40% of components are ignored); stack only if the request names it; notes only if they share a distinctive word (or the request says "notes"). The composer labels files "Investigation targets (matched by name only; confirm...)".
- Model prompts use abstract rules ("don't do A" never becomes "only B"), never concrete examples: Qwen copied "don't retry 4xx / max 2 retries" into an unrelated auth request when those literals were in the rules.
- `ModelOutput.jsonObject` closes slipped brackets (`..."}` for `..."]}`, `"}}`): fallbacks on 15 moderate runs went 3/15 (before) -> 8/15 (after the prompt change) -> 0/15 (with repair).
- Evals: `SemanticEvaluationTests` (REFINE_RUN_LOCAL_MODEL_EVALUATION=1, writes /tmp/semantic-eval.txt) runs 6 requests with an unrelated-audio/history workspace: previous commit failed 26 checks, current 0. Wording-brittle old marker "without changing" in `testPromptEngineeringBaselineEvaluation` can fail when Qwen writes "without altering" (constraint is still present).
- Latency: validator adds ~10 ms; compact prompt +41 tokens. Machine noise dominates (same code ranged complex 15.9-19.9 s, throttled runs up to 26-33 s); back-to-back A/B: previous commit moderate 8.4-9.6 s, complex 14.6-15.5 s; this commit moderate 10.1-11.5 s, complex 15.9-16.2 s in the first clean run.

---

## Website (`website/`)

Official landing page, added 2026-11-09. Next.js 16, TypeScript, Tailwind 4, Motion; fully static, no backend. It is independent of the Swift package. See `website/README.md`.

- Deploy on Vercel with Root Directory `website`. Set `NEXT_PUBLIC_SITE_URL` to the real domain (none chosen yet; canonical and Open Graph URLs depend on it).
- **Blocker before launch: there is no GitHub release.** Every Download button goes to `NEXT_PUBLIC_DOWNLOAD_URL`, defaulting to `/releases/latest`, which redirects to an empty releases page until a build is published. The app is ad-hoc signed, so a public download also needs Developer ID signing and notarization or Gatekeeper will block it.
- Visual direction: true black page, white type, inspired by https://constellagent.vercel.app/ but recolored and adapted. Only Refyn's own UI and the "After" prompts are white (`.app-light` in `globals.css` restores the app's light tokens). Display type is Instrument Serif italic via `next/font`; body stays on the system San Francisco stack. A black notch vanishes on black, so navigation is a hairline bar, not a notch.
- The hero animation loops continuously and pauses while scrolled away; the interactive demo below it does not autoplay. `UnderTheHood.tsx` describes the real optimizer pipeline and model specs, so update it if `PromptOptimizer` or the Qwen models change.
- `demo-video/` is a separate Remotion project: a silent 26-second, 1080p X demo that opens on the chat-app "improve my prompt" problem with a timed script in `VOICEOVER.md`. Its output in `demo-video/out/` is gitignored; render with the command in that file (the long timeout is needed on a cold Chrome start).
- The notch demo is simulated: prewritten output (`src/content/prompts.ts`) and shortened timing, stated on the page.
- `src/lib/motion.ts` copies `Theme.Motion`, and `RefynPanel` copies the SwiftUI layout. Update them if the app's notch or panel changes. Feature copy must match what the current build ships.
- Verified: `tsc`, ESLint, production build; desktop and 390 px phone in a browser; Lighthouse mobile 97-98 performance and 100 accessibility, best practices, and SEO. Reduced-motion behavior is implemented but was not exercised in a browser.
