import type { ReactNode } from "react";
import { AbsoluteFill, Interactive, interpolate, random, Sequence, useCurrentFrame } from "remotion";

import { RefynMark } from "./icons";
import { clamp, colors, ease, fonts } from "./theme";

const centered = { alignItems: "center", justifyContent: "center" } as const;

/** One line, full frame, on a hard cut. It is legible from its first frame, so it works as the autoplay thumbnail. */
const Slam = ({ name, children, inverted = false, size = 232 }: { name: string; children: ReactNode; inverted?: boolean; size?: number }) => {
  const frame = useCurrentFrame();

  return (
    <AbsoluteFill style={{ ...centered, background: inverted ? colors.white : colors.black, color: inverted ? colors.black : colors.white }}>
      <Interactive.Div
        name={name}
        style={{
          fontFamily: fonts.display,
          fontStyle: "italic",
          fontSize: size,
          lineHeight: 1.06,
          textAlign: "center",
          whiteSpace: "nowrap",
          scale: interpolate(frame, [0, 8], [1.08, 1], { ...clamp, easing: ease }),
        }}
      >
        {children}
      </Interactive.Div>
    </AbsoluteFill>
  );
};

export const Problem = () => (
  <AbsoluteFill>
    <Sequence name="Better prompts" durationInFrames={55}>
      <Slam name="Problem line" size={150}>
        You shouldn&apos;t have to
        <br />
        prompt for better prompts.
      </Slam>
    </Sequence>
    <Sequence name="Through your agents" from={55} durationInFrames={30}>
      <Slam name="Agents line" size={210} inverted>
        Through your agents?
      </Slam>
    </Sequence>
    <Sequence name="Expensive" from={85} durationInFrames={25}>
      <Slam name="Expensive">Expensive.</Slam>
    </Sequence>
    <Sequence name="Messy" from={110} durationInFrames={25}>
      <Slam name="Messy" inverted>
        Messy.
      </Slam>
    </Sequence>
  </AbsoluteFill>
);

const statements = ["Local Qwen3.", "$0 per prompt.", "Works offline."];

export const Statements = () => (
  <AbsoluteFill>
    {statements.map((statement, index) => (
      <Sequence key={statement} name={statement} from={index * 24} durationInFrames={24}>
        <Slam name={statement} inverted={index === 1}>
          {statement}
        </Slam>
      </Sequence>
    ))}
  </AbsoluteFill>
);

const Particles = ({ frame }: { frame: number }) => (
  <svg viewBox="0 0 1920 1080" style={{ position: "absolute", inset: 0 }}>
    {Array.from({ length: 110 }, (_, index) => {
      const startX = random(`x${index}`) * 1920;
      const startY = random(`y${index}`) * 1080;
      const offset = random(`o${index}`);
      const speed = 0.005 + random(`s${index}`) * 0.006;
      const progress = (frame * speed + offset) % 1;
      const pull = progress * progress;
      return (
        <circle
          key={index}
          cx={startX + (960 - startX) * pull}
          cy={startY + (20 - startY) * pull}
          r={1 + random(`r${index}`) * 1.8}
          fill="#fff"
          opacity={(0.25 + random(`b${index}`) * 0.55) * interpolate(progress, [0, 0.12, 0.85, 1], [0, 1, 1, 0])}
        />
      );
    })}
  </svg>
);

export const EndCard = () => {
  const frame = useCurrentFrame();

  return (
    <AbsoluteFill style={{ ...centered, flexDirection: "column", background: colors.black, color: colors.white }}>
      <Particles frame={frame} />
      <div
        style={{
          position: "absolute",
          top: 0,
          left: "50%",
          translate: "-50% 0",
          width: 420,
          height: 72,
          borderRadius: "0 0 26px 26px",
          background: colors.white,
          color: colors.black,
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          padding: "0 30px",
          boxSizing: "border-box",
        }}
      >
        <RefynMark size={28} />
        <div style={{ width: 12, height: 12, borderRadius: 12, background: colors.black }} />
      </div>
      <Interactive.Div name="Headline" style={{ fontFamily: fonts.display, fontStyle: "italic", fontSize: 176, lineHeight: 1.04, textAlign: "center", position: "relative" }}>
        <div style={{ color: colors.muted, scale: interpolate(frame, [0, 8], [1.06, 1], { ...clamp, easing: ease }) }}>Optimized prompts.</div>
        <div style={{ opacity: interpolate(frame, [12, 13], [0, 1], clamp), scale: interpolate(frame, [12, 20], [1.06, 1], { ...clamp, easing: ease }) }}>Completely free.</div>
      </Interactive.Div>
      <Interactive.Div
        name="Call to action"
        style={{
          position: "relative",
          marginTop: 54,
          display: "flex",
          alignItems: "center",
          gap: 18,
          fontFamily: fonts.sans,
          fontSize: 42,
          fontWeight: 600,
          opacity: interpolate(frame, [26, 32], [0, 1], clamp),
        }}
      >
        <RefynMark size={36} />
        Refyn
        <span style={{ color: colors.muted, fontWeight: 400, marginLeft: 12 }}>github.com/Youseph-Elkhouly/Refyn</span>
      </Interactive.Div>
    </AbsoluteFill>
  );
};
