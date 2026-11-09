# Refyn demo voiceover

19 seconds, silent video. Say each line with energy and don't leave gaps. Timestamps are when each line should start.

| Time | Say | On screen |
| --- | --- | --- |
| 0:00 | Your AI isn't dumb. | "Your AI isn't dumb." |
| 0:01 | Your prompt is. | "Your prompt is." |
| 0:02 | You keep typing this. | The rough prompt, swallowed by the notch |
| 0:03.5 | Refyn lives in your notch. | The Mac, then a fast zoom as the notch opens |
| 0:05 | Type anything, hit Optimize… | The request types in, Optimize is clicked |
| 0:07 | …and you get a real brief. | The finished prompt, with the camera moving down it |
| 0:10 | Copy it into your agent. Done. | Copy, collapse, paste into the terminal |
| 0:12.5 | Local Qwen. No API keys. Works offline. | One line per beat |
| 0:15 | Refyn. Optimized prompts, completely free. | End card |
| 0:17 | Link below. | The GitHub link stays on screen |

Render again with:

    npx remotion render RefynDemo out/refyn-demo.mp4 --codec=h264 --crf=16 --pixel-format=yuv420p --timeout=180000
