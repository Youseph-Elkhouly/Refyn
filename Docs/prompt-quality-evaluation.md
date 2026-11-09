# Prompt quality evaluation — 2026-11-08

Local mlx-community/Qwen3-4B-4bit; Advanced mode; no workspace; warm model; one sampled run per input before and after. Baseline is the dirty working tree at task start, not an earlier released binary. No cloud inference. Latencies include generation and optimizer checks, excluding warm-up. Sampling and machine load limit timing conclusions.

## Root causes

- Basic and lightweight Auto plans could contain tasks and verification but the composer hid them behind technique flags. The Basic regression test now checks both survive.
- Raw Qwen output included generic acceptance criteria and verification even when its task sequence was useful. Compact instructions discouraged detail; there was no quality gate.
- The composer manufactured a placeholder Example report whenever few-shot was selected.
- Semantic completion manufactured a Confirmed by a test or inspection criterion. Informal dont mess up the design was not recognized as preservation.
- Vague improvement requests could receive unrequested new capabilities as implementation tasks. These now become conditional investigation proposals rather than silently chosen requirements.
- Playbooks invented numerical timing and performance targets. They now describe qualitative goals and measurement methods.
- In the baseline, schema and invention checks deleted no model tasks. Semantic validation removed one verification item across eight inputs. The supplied shallow output was not reproduced verbatim in Advanced mode; Basic rendering loss is covered separately.

## Measurements

Stock criteria counts acceptance lines matched by the generic-language detector, not a comprehensive human quality score. Stage columns count tasks after parsing / schema / semantic checks / invention guard.

| Request | Before seconds | After seconds | Stock criteria before → after | After task stages |
|---|---:|---:|---:|---|
| Exact notch report | 13.15 | 14.08 | 3 → 0 | 5/5/5/5 |
| Slow buggy app | 10.97 | 10.96 | 1 → 0 | 5/5/5/5 |
| UI appearance | 14.70 | 13.47 | 0 → 0 | 5/5/5/5 |
| Intermittent API | 11.40 | 12.49 | 0 → 1 | 5/5/5/5 |
| Code cleanup | 9.65 | 10.36 | 1 → 1 | 3/3/3/3 |
| Odd animation | 11.26 | 14.90 | 0 → 0 | 4/4/4/4 |
| Login security | 11.57 | 15.49 | 0 → 0 | 5/5/5/5 |
| Slow database | 10.58 | 18.59 | 1 → 1 | 5/5/5/5 |

Mean latency: 11.66s before → 13.79s after. Calls: 8 → 8 across eight requests. Quality repair uses no extra inference.

Real inference assertions check that every retained task title and verification step reaches the final prompt, no unsupported file references survive, no detected stock criterion remains, and no placeholder report appears. Unit tests cover Basic rendering, Custom opt-in, a simple rename, unsupported numerical targets, supplied target retention, and the exact notch request.

## Exact notch — actual before output

~~~text
You are a senior engineer working in the current repository. Make focused, production-quality changes that follow the existing patterns.

## Objective
Test and fix the Notch app's bugs and performance issues without altering its design.

## Suggested approach (adjust if the code shows a better fit)
- Test the app's performance under different conditions
- Identify and resolve any issues causing the app to feel buggy or slow
- Ensure all features work as expected without changing the UI or layout

## Constraints
- Dont mess up the design
- Dont mess up the design

## Stage 1 — Inspect
Read the files involved and list the ones you plan to change, with a one-line plan for each. Keep it brief and observable; no private reasoning.

## Working method
Work in short act–observe cycles: search and read the relevant code before editing, make one focused change, run the relevant command, read its output, then decide the next step. Base each step on what you observed, not on assumptions.

## Stage 2 — Implement
1. Reproduce the issues — Test the Notch app to identify specific bugs and performance issues.
2. Analyze the issues — Review the app's behavior to determine the root cause of the bugs and slowness. (after 1)
3. Fix the identified issues — Implement solutions to resolve the bugs and improve performance. (after 2)
4. Verify the fixes — Test the app again to ensure the issues are resolved and the design remains unchanged. (after 3)

## Stage 3 — Verify
- Test the Notch app for bugs and performance issues before and after the fix
- Ensure the app's UI and layout are identical to the original design

## Fix loop
If verification fails: read the failure, fix the cause, and verify again. Stop after 3 attempts and report what still fails and why, instead of continuing or weakening tests.

## Before finishing
Review your own diff against each requirement and constraint above. Fix anything missing or out of scope, and remove unrelated changes.

## Acceptance criteria
- [ ] The Notch app runs smoothly without bugs
- [ ] All features function as expected
- [ ] The app's design remains unchanged
- [ ] Confirmed by a test or inspection: dont mess up the design.

## Stage 4 — Report
- Files changed, one line each on what changed.
- Commands and tests run, with results.
- Assumptions made and anything left unresolved.
~~~

## Exact notch — actual after output

~~~text
You are a senior engineer working in the current repository. Make focused, production-quality changes that follow the existing patterns.

## Objective
Test and fix the Notch app's bugs and performance issues without altering its design.

## Suggested approach (adjust if the code shows a better fit)
- Check for any error messages or logs that may indicate the source of the problem
- Investigate the cause of the weird opening and closing behavior
- Ensure all fixes do not affect the app's design
- Investigate whether this proposal addresses a confirmed problem: Implement fixes. Confirm scope before implementing it.
- Inspect transition timing and state changes; exercise interruptions and rapid reversals. Check focus and lifecycle handling if the transition opens or closes a window.
- Profile the reported slow path before changing it; compare the same scenario before and after and report measurements without inventing a target.

## Constraints
- Dont mess up the design

## Stage 1 — Inspect
Read the files involved and list the ones you plan to change, with a one-line plan for each. Keep it brief and observable; no private reasoning.

## Working method
Work in short act–observe cycles: search and read the relevant code before editing, make one focused change, run the relevant command, read its output, then decide the next step. Base each step on what you observed, not on assumptions.

## Stage 2 — Implement
1. Reproduce the issues — Test the Notch app to identify specific bugs and performance issues.
2. Collect diagnostic information — Gather error messages, logs, and user feedback to understand the root cause of the issues. (after 1)
3. Investigate the cause — Analyze the app's code and performance to determine why the Notch app is slow and feels weird when opening and closing. (after 2)
4. Add regression tests — Create tests to ensure the fixes do not introduce new issues.

## Stage 3 — Verify
- Check that the app's design is unchanged after fixes
- Run the relevant existing tests and build; report commands, results and checks that could not run.
- Replay each reproduced failure after the fix and exercise adjacent existing interactions; distinguish automated regression coverage from manual observations.
- Compare the affected interface before and after to verify the user's visual constraints.

## Fix loop
If verification fails: read the failure, fix the cause, and verify again. Stop after 3 attempts and report what still fails and why, instead of continuing or weakening tests.

## Before finishing
Review your own diff against each requirement and constraint above. Fix anything missing or out of scope, and remove unrelated changes.

## Acceptance criteria
- [ ] The app's design remains unchanged
- [ ] Repeated and interrupted transitions reach the requested state without visible snapping or unexpected state changes.

## Stage 4 — Report
- Files changed, one line each on what changed.
- Commands and tests run, with results.
- Assumptions made and anything left unresolved.
~~~

## Earlier verification (2026-11-08)

The earlier pass built successfully and ran 149 tests with 15 opt-in skips and no failures. Its recorded replay covered eight cases (0.096 seconds mean without inference), and its live model run covered eight requests. Those are historical results; the final verification below uses nine cases and the final code tree.

## Final verification (2026-11-09)

The replay crash was in the test harness, not optimizer inference. The crash report points to `ShallowQualityEvaluationTests.swift:48`: it indexed `[1]` from the components split on `\nPARSED\n`. A captured chunk without that delimiter caused Swift's array subscript precondition to terminate the test process. Replay now validates each case header, `PARSED` and `SCHEMA` section, duplicate case number, and JSON decode, and reports malformed or truncated captures as ordinary test failures. Regression tests cover a missing `PARSED` marker and invalid plan JSON. The full nine-case capture replayed through the final optimizer successfully.

The replay also exposed a false generic-criterion match: the detector classified the user's quoted symptom “doesnt work properly” as a generic acceptance line. Symptom checks now produce observable post-fix checks rather than copying that phrase into acceptance criteria. Generic boilerplate criteria are filtered, and preservation criteria are deduplicated per user-specified target so keeping the progress UI cannot accidentally remove the separate upload API preservation criterion.

### Fresh Qwen3-4B run

Advanced mode, warm local `mlx-community/Qwen3-4B-4bit`, no workspace, one sample per case. Each request used one model call. All nine raw outputs extracted and decoded as JSON, passed schema validation, and reached the guarded and final stages. No fallback or model retry occurred.

| Case | Request | Qwen + optimizer latency | Final prompt words |
|---:|---|---:|---:|
| 0 | Vague Notch bug/performance request | 14.75s | 441 |
| 1 | App slow and buggy | 13.39s | 313 |
| 2 | Make UI look better | 12.86s | 219 |
| 3 | Intermittent API failures | 12.27s | 244 |
| 4 | Refactor without breaking behavior | 9.22s | 205 |
| 5 | Animation feels weird | 14.34s | 322 |
| 6 | Make login more secure | 12.31s | 222 |
| 7 | Slow database operations | 12.48s | 293 |
| 8 | Slow window/view changes, unresponsive buttons, UI freezes | 14.52s | 484 |

Mean latency was **12.90s** (median 12.86s), versus the previously reported 9.4s: **3.50s slower per request**. These are single sampled runs, not a statistically controlled benchmark. The prompt-length mean after final replay was 304.8 words (range 205–484).

| Quality dimension | Final result |
|---|---|
| Intent preservation | 9/9 replayed prompts retained the request terms required by `RequestAnalysis`. |
| Reported symptoms | The final multi-symptom case retained and checked all four markers: opening windows, switching views, buttons, and UI freezes. The exact earlier Notch request retained its slow/opening/closing/nonworking symptoms. |
| Acceptance criteria | No criteria matched the expanded generic-language detector in the final replay. The detector is heuristic, not a human quality guarantee. |
| Actionability | Each of the nine prompts had tasks and verification, and the replay asserted that each retained task and verification item appeared in the rendered prompt. |
| JSON and pipeline | 9/9 produced raw, parsed, schema, semantic, guarded, and final records; zero fallbacks. |
| Context accuracy | No workspace was selected; 0 unverified file references survived. Workspace-context relevance was not measured in this run. |
| Human review | Cases 2, 3, 5, and 7 still contain overly specific suggested work for the vague input: the UI request adds state/accessibility guidance; API failure adds a recent-change window and load testing; animation adds cross-platform checks; database slowness presumes query/index/resource investigations. These are not confirmed codebase facts, but they can read as assumed scope. |
| Conciseness | Two prompts remain long at 441 and 484 words, with some overlap between suggestions, tasks, and verification. No generic example report or staged workflow was rendered. |

### Verification commands

- `swift build` — passed.
- `swift test` — 152 tests, 15 opt-in skips, 0 failures.
- `REFINE_QUALITY_REPLAY=/tmp/refyn-quality-final-run.txt REFINE_QUALITY_REPLAY_FINAL_OUTPUT=/tmp/refyn-quality-final-rendered.txt swift test --filter ShallowQualityEvaluationTests/testReplayRecordedBaseline` — passed, 9/9 captured responses; deterministic replay averaged 0.094s per request.
- `REFINE_RUN_LOCAL_MODEL_EVALUATION=1 QUALITY_EVAL_MODE=advanced QUALITY_EVAL_OUTPUT=/tmp/refyn-quality-final-run.txt swift test --filter ShallowQualityEvaluationTests/testRealVagueRequests` — passed, 9/9 live model requests; 12.90s mean.
- `git diff --check` — passed for the optimizer, replay tests, and evaluation report.

Raw responses and intermediate stages are in `/tmp/refyn-quality-final-run.txt`; final prompts replayed through the last deterministic changes are in `/tmp/refyn-quality-final-rendered.txt`. No UI files were changed or visually tested.

### Remaining limitations

The heuristic acceptance-criterion gate does not prove every generated task is technically correct or tightly scoped. Human review still found the four over-specific cases above, and the longest prompts remain repetitive. Do not treat 9/9 automated checks as 9/9 human-rated quality passes. No workspace-context live-model run or UI interaction test was performed in this pass.
