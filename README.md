# Refyn

**Better prompts. On-device.**

Refyn is a native macOS assistant that lives in the notch, turns rough instructions into prompts for coding agents, and uses selected workspace metadata and notes for relevant context. Prompt inference runs locally through MLX Swift; there are no API keys, cloud inference requests, or per-prompt charges.

Open with Control-Option-Space, choose a workspace, type or dictate, Optimize, compare, then copy or save.

## Requirements

- macOS 14+ on Apple Silicon, Xcode 16 / Swift 6
- About 8 GB of available unified memory recommended for Qwen3 4B 4-bit
- About 2.3 GB disk space for the model download
- Node.js 20+ for workspace analysis
- Git optional; improves workspace file discovery

The model is downloaded from https://huggingface.co/mlx-community/Qwen3-4B-4bit, stored in the Refyn Application Support folder, and loaded locally. First setup requires internet; optimization works offline after the download completes.

## Build and run

Run Scripts/build-app.sh to build the helper, Swift app, MLX Metal kernels, and .build/Refyn.app. Then open .build/Refyn.app.

Development checks:

- In RefineHelper, run npm ci and npm test.
- Run swift build and swift test for Swift app/core tests.

The Qwen integration test downloads the model once and runs real on-device generation, including after unloading and reloading in offline mode. It takes several minutes on first run. The SwiftPM test runner does not discover MLX's Metal shader bundle automatically, so stage the shaders after building the tests:

- Run swift test; the integration test skips unless opted in.
- Run Scripts/build-mlx-metallib.sh to compile and stage MLX Metal kernels.
- Run REFINE_RUN_LOCAL_MODEL_INTEGRATION=1 swift test --filter LocalInferenceTests/testDownloadAndRunModelThenRunOffline.
- Run REFINE_RUN_LOCAL_MODEL_EVALUATION=1 swift test --filter LocalInferenceTests/testPromptEngineeringBaselineEvaluation for the seven-case quality baseline.

The checked-in baseline covers rough features, ambiguity, a complex feature, bug fixing, refactoring, a short rename, and a verification workflow. On the current Apple Silicon machine, all seven retained their required request terms, no unverified code references survived, the short request stayed at 23 characters, and all four cases marked for structured work produced tasks and verification. The four model-backed cases averaged about 14.9 seconds. This baseline does not justify fine-tuning; the short Auto/Basic path correctly skips model loading and stays deterministic.

Existing Refine data moves to the Refyn Application Support folder on first launch; the database, speech models, workspace data, and downloaded Qwen model are preserved. First launch: the notch appears as a small pill, or at the top center on a display without a notch. Choose Settings › Model › Download model, then optimize prompts. A workspace is optional. Add one from the workspace menu to include relevant project context. Download a speech model in Settings › Voice to dictate (hold Control-Option-D).

## Architecture

- RefineCore contains prompt plans, workspace models, context retrieval, persistence, and prompt engineering.
- The SwiftUI and AppKit app contains the notch, settings, workspace views, and local model/audio services.
- The Node.js / TypeScript helper performs local workspace analysis through a versioned JSON-lines protocol.
- SharedSchemas contains the helper protocol and CodebaseGraph schema.

The model layer is modular behind LLMProvider. Qwen3 returns a structured plan, and Refyn validates tasks and dependencies, drops code references that cannot be confirmed in the selected workspace, then composes the final prompt locally. Invalid model output uses the deterministic local builder with a visible notice; model load/runtime failures are shown as errors. Matching prior results are cached.

Prompt modes:

- Auto chooses a concise direct rewrite for simple prompts and more techniques as complexity rises.
- Basic improves clarity and constraints without unnecessary expansion.
- Advanced adds ordered implementation stages, dependencies, acceptance criteria, verification, and a bounded retry workflow.
- Custom applies only the techniques selected in the editor.

Workspace files are scanned locally. Refyn retrieves bounded component metadata, matching symbols and paths, project notes, and user instructions; it does not send full repository files to a model. The analyzer excludes secrets, credential files, node_modules, generated/build output, binaries, and files over 512 KB. Workspace source is treated as untrusted reference data in the model prompt.

## Data and privacy

- App data is in the Refyn Application Support folder: database, workspace summaries/indexes, speech models, and Qwen model.
- Refyn does not write to the selected repository. Removing a workspace deletes only Refyn's records.
- Dictation is recorded only while requested, transcribed on-device, and is never sent to the language model automatically.
- Optimization uses selected workspace context and the local model only. Downloading model/speech weights is the only network setup step.

## Known limitations

- Python and Swift source analysis is pattern-based; Go, Rust, Java, and other languages are detected but not deeply analyzed.
- The app is ad-hoc signed and not sandboxed; it reads only workspaces the user selects.
- MLX inference is intended for Apple Silicon. The app reports a clear runtime error if the local model cannot be loaded.

## Third-party

- MLX Swift LM (MIT): https://github.com/ml-explore/mlx-swift-lm
- Qwen3 4B 4-bit (Apache-2.0): https://huggingface.co/mlx-community/Qwen3-4B-4bit
- GRDB.swift (MIT): https://github.com/groue/GRDB.swift
- WhisperKit (MIT): https://github.com/argmaxinc/WhisperKit
- TypeScript (Apache-2.0): https://github.com/microsoft/TypeScript
