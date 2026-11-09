import { AbsoluteFill, Interactive, interpolate, interpolateColors, random, useCurrentFrame } from "remotion";

import { RefynMark } from "./icons";
import { clamp, colors, ease, fonts } from "./theme";
import { request, scenes } from "./timeline";

const centered = { background: colors.black, alignItems: "center", justifyContent: "center", color: colors.white } as const;

export const Opening = () => {
  const frame = useCurrentFrame();
  const typed = request.slice(0, Math.floor(interpolate(frame, [4, 42], [0, request.length], clamp)));

  return (
    <AbsoluteFill style={{ ...centered, flexDirection: "column", gap: 44, opacity: interpolate(frame, [scenes.opening.duration - 8, scenes.opening.duration], [1, 0], clamp) }}>
      <Interactive.Div name="Rough prompt" style={{ fontFamily: fonts.display, fontStyle: "italic", fontSize: 124, lineHeight: 1.05, height: 132, whiteSpace: "nowrap" }}>
        {typed}
        <span style={{ display: "inline-block", width: 4, height: 100, marginLeft: 8, verticalAlign: -12, background: colors.white, opacity: frame < 46 || Math.floor(frame / 15) % 2 === 0 ? 1 : 0 }} />
      </Interactive.Div>
      <Interactive.Div
        name="Vague line"
        style={{
          fontFamily: fonts.sans,
          fontSize: 48,
          color: colors.muted,
          opacity: interpolate(frame, [62, 74], [0, 1], clamp),
          translate: `0px ${interpolate(frame, [62, 76], [14, 0], { ...clamp, easing: ease })}px`,
        }}
      >
        Vague in. Vague out.
      </Interactive.Div>
    </AbsoluteFill>
  );
};

const statements = ["On your Mac.", "No API keys.", "Works offline."];

export const Statements = () => {
  const frame = useCurrentFrame();

  return (
    <AbsoluteFill style={{ ...centered, flexDirection: "column", gap: 34, opacity: interpolate(frame, [0, 6], [0, 1], clamp) }}>
      <Interactive.Div name="Model label" style={{ fontFamily: fonts.mono, fontSize: 36, color: colors.muted, marginBottom: 18 }}>
        ## Qwen3, running locally
      </Interactive.Div>
      {statements.map((statement, index) => {
        const start = 6 + index * 46;
        return (
          <Interactive.Div
            key={statement}
            name={statement}
            style={{
              fontFamily: fonts.display, fontStyle: "italic",
              fontSize: 168,
              lineHeight: 1.04,
              opacity: interpolate(frame, [start, start + 9], [0, 1], clamp),
              translate: `0px ${interpolate(frame, [start, start + 14], [20, 0], { ...clamp, easing: ease })}px`,
              color: interpolateColors(frame, [start + 40, start + 48], index === statements.length - 1 ? [colors.white, colors.white] : [colors.white, colors.muted]),
            }}
          >
            {statement}
          </Interactive.Div>
        );
      })}
    </AbsoluteFill>
  );
};

const Particles = ({ frame }: { frame: number }) => (
  <svg viewBox="0 0 1920 1080" style={{ position: "absolute", inset: 0 }}>
    {Array.from({ length: 110 }, (_, index) => {
      const startX = random(`x${index}`) * 1920;
      const startY = random(`y${index}`) * 1080;
      const offset = random(`o${index}`);
      const speed = 0.0028 + random(`s${index}`) * 0.0036;
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
    <AbsoluteFill style={{ ...centered, flexDirection: "column", opacity: interpolate(frame, [0, 8], [0, 1], clamp) }}>
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
          scale: interpolate(frame, [4, 22], [0.82, 1], { ...clamp, easing: ease }),
          transformOrigin: "top center",
        }}
      >
        <RefynMark size={28} />
        <div style={{ width: 12, height: 12, borderRadius: 12, background: colors.black }} />
      </div>
      <Interactive.Div name="Headline" style={{ fontFamily: fonts.display, fontStyle: "italic", fontSize: 176, lineHeight: 1.04, textAlign: "center", position: "relative" }}>
        <div style={{ color: colors.muted, opacity: interpolate(frame, [10, 22], [0, 1], clamp) }}>Optimized prompts.</div>
        <div style={{ opacity: interpolate(frame, [28, 40], [0, 1], clamp), translate: `0px ${interpolate(frame, [28, 44], [18, 0], { ...clamp, easing: ease })}px` }}>Completely free.</div>
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
          opacity: interpolate(frame, [56, 68], [0, 1], clamp),
        }}
      >
        <RefynMark size={36} />
        Refyn
        <span style={{ color: colors.muted, fontWeight: 400, marginLeft: 12 }}>github.com/Youseph-Elkhouly/Refyn</span>
      </Interactive.Div>
    </AbsoluteFill>
  );
};
