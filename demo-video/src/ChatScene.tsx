import type { ReactNode } from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";

import { clamp, colors, ease, fonts } from "./theme";

const firstRequest = "improve my prompt: my app is slow and buggy, fix it";
const secondRequest = "no, i need it for my coding agent";

const firstReply = `Great question! Here's an improved version of your prompt:

"Please analyze my application to identify any performance issues and bugs, and then resolve them."

To make it even better, could you share:
• What framework are you using?
• What does "slow" mean here?
• Which bugs are you seeing?`;

const secondReply = `Got it! Here's a revised version for a coding agent:

"Act as a senior software engineer. Carefully analyze my application and identify any issues that may be affecting its performance and reliability. Then, using best practices, please`;

const beats = {
  firstSend: 30,
  firstReplyStart: 44,
  firstReplyEnd: 112,
  secondTypeStart: 112,
  secondTypeEnd: 128,
  secondSend: 130,
  secondReplyStart: 140,
  secondReplyEnd: 182,
};

const reveal = (text: string, frame: number, start: number, end: number, from = 0) => text.slice(0, Math.floor(interpolate(frame, [start, end], [from, text.length], clamp)));

const UserMessage = ({ children }: { children: ReactNode }) => (
  <div style={{ alignSelf: "flex-end", maxWidth: 1020, padding: "22px 34px", borderRadius: 34, background: "#2a2a2a" }}>{children}</div>
);

const Thinking = ({ frame }: { frame: number }) => <div style={{ width: 26, height: 26, borderRadius: 26, background: colors.white, opacity: 0.55 + Math.sin(frame / 2) * 0.45 }} />;

/** A generic chat app, on purpose: no logos, only the conversation everyone recognizes. */
export const ChatScene = () => {
  const frame = useCurrentFrame();
  const isFirstSent = frame >= beats.firstSend;
  const isSecondSent = frame >= beats.secondSend;

  const inputText = !isFirstSent
    ? reveal(firstRequest, frame, 0, 26, 18)
    : frame >= beats.secondTypeStart && !isSecondSent
      ? reveal(secondRequest, frame, beats.secondTypeStart, beats.secondTypeEnd)
      : "";

  return (
    <AbsoluteFill style={{ background: "#141414", color: colors.white, fontFamily: fonts.sans, scale: interpolate(frame, [0, 182], [1, 1.05], clamp) }}>
      <div style={{ height: 96, flexShrink: 0, display: "flex", alignItems: "center", paddingLeft: 320, fontSize: 36, fontWeight: 600 }}>ChatGPT</div>
      <div style={{ flex: 1, minHeight: 0, overflow: "hidden", display: "flex", flexDirection: "column", justifyContent: "flex-end", alignItems: "center" }}>
        <div style={{ width: 1280, display: "flex", flexDirection: "column", gap: 44, fontSize: 38, lineHeight: 1.36, paddingBottom: 36 }}>
          {isFirstSent && <UserMessage>{firstRequest}</UserMessage>}
          {frame >= beats.firstSend + 2 && frame < beats.firstReplyStart && <Thinking frame={frame} />}
          {frame >= beats.firstReplyStart && <div style={{ whiteSpace: "pre-wrap" }}>{reveal(firstReply, frame, beats.firstReplyStart, beats.firstReplyEnd)}</div>}
          {isSecondSent && <UserMessage>{secondRequest}</UserMessage>}
          {frame >= beats.secondSend + 2 && frame < beats.secondReplyStart && <Thinking frame={frame} />}
          {frame >= beats.secondReplyStart && <div style={{ whiteSpace: "pre-wrap" }}>{reveal(secondReply, frame, beats.secondReplyStart, beats.secondReplyEnd)}</div>}
        </div>
      </div>
      <div
        style={{
          flexShrink: 0,
          display: "flex",
          justifyContent: "center",
          paddingBottom: 44,
          translate: `0px ${interpolate(frame, [beats.firstSend - 2, beats.firstSend + 8], [-400, 0], { ...clamp, easing: ease })}px`,
          scale: interpolate(frame, [beats.firstSend - 2, beats.firstSend + 8], [1.26, 1], { ...clamp, easing: ease }),
        }}
      >
        <div style={{ width: 1280, height: 112, boxSizing: "border-box", borderRadius: 56, background: "#2a2a2a", display: "flex", alignItems: "center", padding: "0 18px 0 44px", fontSize: 38 }}>
          <div style={{ flex: 1, whiteSpace: "nowrap", color: inputText ? colors.white : colors.muted }}>{inputText || "Ask anything"}</div>
          <div style={{ width: 76, height: 76, borderRadius: 76, display: "grid", placeItems: "center", background: inputText ? colors.white : "#4a4a4a", color: colors.black }}>
            <svg width="34" height="34" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <path d="M8 13.5v-11M3.5 7 8 2.5 12.5 7" />
            </svg>
          </div>
        </div>
      </div>
    </AbsoluteFill>
  );
};
