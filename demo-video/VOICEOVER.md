# Refyn demo voiceover

26 seconds, silent video. Keep the energy up and don't leave gaps. Timestamps are when each line should start.

| Time | Say | On screen |
| --- | --- | --- |
| 0:00 | We've all done this. Paste your prompt in and ask it to improve it. | "improve my prompt…" sent to a chat app |
| 0:04 | Then you go back and forth. | A second message, more streaming text |
| 0:06 | You shouldn't have to prompt for better prompts… | "You shouldn't have to prompt for better prompts." |
| 0:08 | …through your agents. | "Through your agents?" |
| 0:09 | It's expensive. | "Expensive." |
| 0:10 | And it's messy. | "Messy." |
| 0:10.5 | So we built Refyn. It lives in your notch. | The Mac, then a fast zoom as the notch opens |
| 0:13 | Type anything, hit Optimize… | The request types in, Optimize is clicked |
| 0:14.5 | …and you get a real brief. | The finished prompt, with the camera moving down it |
| 0:17 | Copy it into your agent. Done. | Copy, collapse, paste into the terminal |
| 0:19.5 | Local Qwen. Zero dollars per prompt. Works offline. | One line per beat |
| 0:22 | Refyn. Optimized prompts, completely free. | End card |
| 0:24 | Link below. | The GitHub link stays on screen |

Render again with:

    npx remotion render RefynDemo out/refyn-demo.mp4 --codec=h264 --crf=16 --pixel-format=yuv420p --timeout=180000
