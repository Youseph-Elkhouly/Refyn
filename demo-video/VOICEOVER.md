# Refyn demo voiceover

36 seconds, silent video, about 2.5 to 3 words per second. Timestamps are when each line should start.

| Time | Say | On screen |
| --- | --- | --- |
| 0:00 | We all write prompts like this… and then wonder why the agent gets it wrong. | A rough prompt types itself, then "Vague in. Vague out." |
| 0:05 | This is Refyn. It lives in your Mac's notch. | The whole Mac, then the camera moves to the notch |
| 0:08 | Click it, and type whatever's in your head. As messy as you want. | The notch opens and the request types in |
| 0:12 | Hit Optimize. A local Qwen model runs right on your Mac. | "Running locally" |
| 0:16 | And you get a real brief: objective, steps, constraints, and how to verify it. | The camera moves down the finished prompt |
| 0:21 | Copy it straight into Claude Code, Codex, whatever you use. | Copy, the notch collapses, the prompt pastes into the terminal |
| 0:25 | It all runs on your Mac. | "On your Mac." |
| 0:27 | No API keys. | "No API keys." |
| 0:28 | Works offline. | "Works offline." |
| 0:30 | Refyn. Optimized prompts, completely free. | End card |
| 0:33 | Link below. | The GitHub link stays on screen |

Render again with:

    npx remotion render RefynDemo out/refyn-demo.mp4 --codec=h264 --crf=16 --pixel-format=yuv420p --timeout=180000
