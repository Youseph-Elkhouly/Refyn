# Refyn

**Better prompts, made on your Mac.**

Refyn is a native macOS prompt assistant that lives in the notch. It turns rough requests into useful prompts for coding agents, using a local Qwen model and optional context from a workspace you choose. Optimization and dictation run on-device—no API key, cloud inference, or per-prompt fee.

## Download

Get the Apple Silicon QA preview from [GitHub Releases](https://github.com/Youseph-Elkhouly/Refyn/releases/latest). The app package includes the English WhisperKit Base voice model. The same release provides Qwen3 4B as split model assets for offline setup; use the included install guide, or download the model from Settings the first time you run Refyn. The preview is ad-hoc signed and not notarized.

## Get started

1. Open Refyn with **Control–Option–Space**.
2. Choose a workspace if you want project context. You can also use Refyn without one.
3. Type or paste a request, or dictate with the microphone button or **Control–Option–D**.
4. Choose **Auto**, **Basic**, **Advanced**, or **Custom**, then select **Optimize**.
5. Review the result, edit it, copy it, or save it.

If Qwen is not already installed, open **Settings › Model** and download it. The download is about 2.3 GB and requires internet once; after it finishes, optimization works offline. Refyn may ask a few short questions when a request is missing important details. Turn this off under **Settings › Model › Prompts**.

### Prompt modes

| Mode | What it does |
| --- | --- |
| **Auto** | Keeps simple requests concise and adds structure when the task needs it. |
| **Basic** | Clarifies the request without unnecessary scaffolding. |
| **Advanced** | Adds implementation steps and verification when useful. |
| **Custom** | Lets you choose techniques such as examples, task breakdown, or acceptance criteria. |

## Useful features

- **Prompt history:** Search earlier results, reopen them, copy them, or reuse them.
- **Add context:** Add a detail you remembered to an optimized prompt and optimize it again. Refyn saves the new result as a revision and keeps the earlier version in history.
- **Completion alerts:** Opt in under **Settings › Model › Prompts** to receive a macOS notification when optimization finishes.
- **Workspace notes:** Use notes and relevant project context to make prompts more specific. Refyn retrieves bounded context instead of sending whole repository files to the model.

## Models and privacy

- **Prompt optimization:** Qwen3 4B, 4-bit quantized, runs locally through MLX on Apple Silicon. Download it in Settings or install the split archive from the [GitHub release](https://github.com/Youseph-Elkhouly/Refyn/releases/latest). The weights are stored in Refyn’s Application Support folder. An optional smaller Qwen3 model is available in Settings.
- **Voice dictation:** Release packages include the English WhisperKit Base model, so dictation is ready offline. Source builds can download a speech model from **Settings › Voice**. Tiny and Small English models are also available there.
- **Audio:** Recording starts only when you request dictation. Speech is transcribed on this Mac and is not sent to the language model automatically.
- **Workspace context:** Analysis stays local. Refyn uses relevant project metadata, symbols, file paths, notes, and instructions; it excludes secrets and generated files and does not write to the selected repository.

## Requirements

- macOS 14 or later on Apple Silicon
- About 8 GB of available unified memory recommended for Qwen3 4B
- About 2.3 GB of free disk space for the Qwen model download
- Xcode 16 and Swift 6 to build from source
- Node.js 20 or later to build the workspace helper from source; release packages include Node.js
- Git is optional and improves workspace file discovery

## Build and package

Build the app locally:

```sh
Scripts/build-app.sh release
open .build/Refyn.app
```

Create an Apple Silicon QA release with a portable Node runtime, bundled English voice model, app ZIP and DMG, split Qwen model assets, install instructions, and SHA-256 checksums:

```sh
Scripts/package-release.sh 0.1.0
```

Files are written to `.build/release-package/`. Packaging expects the WhisperKit English Base and Qwen3 4B models to already be downloaded. Override their directories when needed:

```sh
REFYN_SPEECH_MODEL_DIR="/path/to/openai_whisper-base.en" \
REFYN_QWEN_MODEL_DIR="/path/to/Qwen3-4B-4bit" \
Scripts/package-release.sh 0.1.0
```

Set `REFYN_QWEN_MODEL_DIR` as well if the Qwen model is outside Refyn’s default Application Support folder. The app ZIP includes the English voice model. Qwen’s roughly 2.1 GB weights are supplied as a split archive beside the app; download every part, join them, and follow the generated `Refyn-0.1.0-Qwen3-4B-4bit-Install.txt` to use Qwen without a first-run model download. The archive is split because GitHub limits each release asset to less than 2 GiB. Qwen can also be downloaded from Settings. QA packages are ad-hoc signed and not notarized. A public release requires Developer ID signing and Apple notarization.

## Development checks

Build the helper and run its tests, then build and test the Swift app:

```sh
(cd RefineHelper && npm ci && npm test)
swift build
swift test
```

The real Qwen tests are opt-in and require the model to be installed. To run the offline load-and-generation test, first build and stage the MLX Metal kernels:

```sh
Scripts/build-mlx-metallib.sh
REFINE_RUN_LOCAL_MODEL_INTEGRATION=1 swift test --filter LocalInferenceTests/testDownloadAndRunModelThenRunOffline
```

Run the prompt baselines with Qwen installed:

```sh
REFINE_RUN_LOCAL_MODEL_EVALUATION=1 swift test --filter LocalInferenceTests/testPromptEngineeringBaselineEvaluation
REFINE_RUN_LOCAL_MODEL_EVALUATION=1 swift test --filter LocalInferenceTests/testClarificationQualityEvaluationEightUnderspecifiedAndTwoClearRequests
REFINE_RUN_LOCAL_MODEL_EVALUATION=1 QUALITY_EVAL_OUTPUT=/tmp/refyn-quality-evaluation.txt swift test --filter ShallowQualityEvaluationTests/testRealVagueRequests
```

Replay a previously recorded response without running inference:

```sh
REFINE_QUALITY_REPLAY=/path/to/recorded-output.txt swift test --filter ShallowQualityEvaluationTests/testReplayRecordedBaseline
```

See [the prompt quality evaluation](Docs/prompt-quality-evaluation.md) for measured outputs, latency, known limitations, and the evaluation method.

## Project structure

- `Sources/Refyn/` — notch app, settings, workspace views, local inference, and dictation.
- `Sources/RefineCore/` — prompt planning, optimization, workspace context, and persistence.
- `RefineHelper/` — local TypeScript helper for workspace analysis.
- `Tests/` — Swift unit, integration, and local-model evaluation tests.

## Current limitations

- Workspace analysis for Python and Swift is pattern-based; several other languages are detected but not deeply analyzed.
- MLX inference requires Apple Silicon. Refyn reports an error if the local model cannot load.
- The app is currently not sandboxed and release builds are ad-hoc signed; only user-selected workspaces are analyzed.

## Third-party software and models

- [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm) — MIT
- [Qwen3 4B 4-bit](https://huggingface.co/mlx-community/Qwen3-4B-4bit) — Apache-2.0
- [WhisperKit](https://github.com/argmaxinc/WhisperKit) — MIT
- [OpenAI Whisper model weights and license](https://github.com/openai/whisper/blob/main/LICENSE) — MIT
- [GRDB.swift](https://github.com/groue/GRDB.swift) — MIT
- [TypeScript](https://github.com/microsoft/TypeScript) — Apache-2.0
