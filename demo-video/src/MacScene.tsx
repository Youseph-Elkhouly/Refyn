import { AbsoluteFill, interpolate, interpolateColors, useCurrentFrame } from "remotion";

import { RefynMark } from "./icons";
import { Panel } from "./Panel";
import { clamp, colors, ease, easeInOut, fonts } from "./theme";
import { mac } from "./timeline";

const display = { width: 1470, height: 956 };
const notch = { width: 200, height: 30, compactWidth: 296 };
const panelWidth = 640;

const cameraTimes = [0, mac.zoomToNotch, mac.atNotch, mac.openNotch, mac.cameraOnPanel, mac.result - 4, mac.result + 26, mac.scrollStart, mac.scrollEnd, mac.cursorAtCopy - 8, mac.closeNotch, mac.cameraOnTerminal];

const MenuBar = () => (
  <div style={{ position: "absolute", inset: "0 0 auto 0", height: 30, display: "flex", alignItems: "center", gap: 18, padding: "0 14px", background: "rgba(255,255,255,0.08)", color: colors.white, fontFamily: fonts.sans, fontSize: 12.5 }}>
    <b>Terminal</b>
    <span>Shell</span>
    <span>Edit</span>
    <span>View</span>
    <span>Window</span>
    <span style={{ marginLeft: "auto", fontVariantNumeric: "tabular-nums" }}>9:41</span>
  </div>
);

const Wallpaper = () => (
  <svg viewBox="0 0 1000 650" preserveAspectRatio="xMidYMid slice" style={{ position: "absolute", inset: 0, width: "100%", height: "100%" }} fill="none">
    <circle cx="780" cy="470" r="330" stroke={colors.wallpaperRing} strokeWidth="58" />
    <circle cx="780" cy="470" r="118" fill={colors.wallpaperRing} />
  </svg>
);

const Terminal = ({ frame }: { frame: number }) => {
  const pasteOpacity = interpolate(frame, [mac.paste, mac.paste + 8], [0, 1], clamp);
  const isPasted = frame >= mac.paste;

  return (
    <div style={{ position: "absolute", left: (display.width - 900) / 2, bottom: 64, width: 900, height: 420, borderRadius: 12, background: colors.terminal, boxShadow: "0 0 0 1px rgba(255,255,255,0.12), 0 22px 60px rgba(0,0,0,0.6)", fontFamily: fonts.mono, fontSize: 15, lineHeight: "26px", color: "#d4d4d4", overflow: "hidden" }}>
      <div style={{ height: 36, display: "flex", alignItems: "center", gap: 8, padding: "0 14px", borderBottom: "1px solid rgba(255,255,255,0.07)" }}>
        {[0, 1, 2].map((dot) => (
          <div key={dot} style={{ width: 12, height: 12, borderRadius: 12, background: "rgba(255,255,255,0.16)" }} />
        ))}
      </div>
      <div style={{ padding: 18 }}>
        <div style={{ color: "#8a8a8a" }}>~/storefront-web</div>
        <div>❯ your-coding-agent</div>
        <div style={{ color: "#8a8a8a", marginTop: 12 }}>Agent ready. What should we work on?</div>
        <div style={{ marginTop: 12 }}>
          <span style={{ color: colors.white }}>&gt; </span>
          {isPasted ? (
            <span style={{ opacity: pasteOpacity }}>## Objective</span>
          ) : (
            <span style={{ display: "inline-block", width: 9, height: 17, verticalAlign: -2, background: colors.white, opacity: Math.floor(frame / 16) % 2 ? 0 : 1 }} />
          )}
        </div>
        <div style={{ opacity: pasteOpacity, paddingLeft: 20 }}>
          <div>Find what is making the app slow and buggy, then fix</div>
          <div>the causes you can confirm.</div>
          <div style={{ color: "#8a8a8a", marginTop: 8 }}>[pasted 13 more lines]</div>
        </div>
      </div>
    </div>
  );
};

const Cursor = ({ frame }: { frame: number }) => (
  <svg
    width="20"
    height="28"
    viewBox="0 0 20 28"
    style={{
      position: "absolute",
      left: 0,
      top: 0,
      transformOrigin: "1px 1px",
      translate: `${interpolate(
        frame,
        [0, mac.zoomToNotch, mac.atNotch, mac.typingEnd, mac.cursorAtOptimize, mac.scrollEnd, mac.cursorAtCopy, mac.closeNotch + 10, mac.cameraOnTerminal],
        [1090, 1090, 735, 1040, 1006, 1006, 468, 620, 1120],
        { ...clamp, easing: easeInOut },
      )}px ${interpolate(
        frame,
        [0, mac.zoomToNotch, mac.atNotch, mac.typingEnd, mac.cursorAtOptimize, mac.scrollEnd, mac.cursorAtCopy, mac.closeNotch + 10, mac.cameraOnTerminal],
        [640, 640, 16, 420, 356, 480, 524, 560, 830],
        { ...clamp, easing: easeInOut },
      )}px`,
      scale: interpolate(
        frame,
        [mac.openNotch - 4, mac.openNotch, mac.openNotch + 4, mac.clickOptimize - 4, mac.clickOptimize, mac.clickOptimize + 4, mac.clickCopy - 4, mac.clickCopy, mac.clickCopy + 4],
        [1, 0.82, 1, 1, 0.82, 1, 1, 0.82, 1],
        clamp,
      ),
    }}
  >
    <path d="M1.5 1.5v21.2l5.2-5 3.5 8 3.6-1.6-3.5-7.9h7.2Z" fill="#000" stroke="#fff" strokeWidth="1.6" strokeLinejoin="round" />
  </svg>
);

/** The whole walkthrough on one continuous Mac, with a camera moving over it. */
export const MacScene = () => {
  const frame = useCurrentFrame();

  const zoom = interpolate(frame, cameraTimes, [0.985, 0.985, 3, 3, 2.02, 2.02, 1.88, 2.4, 2.4, 1.88, 1.88, 1.85], { ...clamp, easing: easeInOut });
  const focusX = 735;
  const focusY = interpolate(frame, cameraTimes, [492, 492, 150, 150, 232, 232, 284, 232, 336, 284, 284, 682], { ...clamp, easing: easeInOut });

  return (
    <AbsoluteFill style={{ background: colors.black }}>
      <div style={{ position: "absolute", left: 0, top: 0, transformOrigin: "0 0", translate: `${960 - focusX * zoom}px ${540 - focusY * zoom}px`, scale: zoom }}>
        <div style={{ position: "absolute", left: -14, top: -14, width: display.width + 28, height: display.height + 30, background: colors.black, borderRadius: "32px 32px 0 0", boxShadow: "0 0 0 2px #3a3a3c" }} />
        <div style={{ position: "absolute", left: -96, top: display.height + 16, width: display.width + 192, height: 26, borderRadius: "0 0 30px 30px", background: "linear-gradient(#4a4a4d, #2a2a2c 55%, #18181a)" }} />

        <div style={{ position: "absolute", left: 0, top: 0, ...display, overflow: "hidden", borderRadius: "18px 18px 0 0", background: colors.desktop }}>
          <Wallpaper />
          <MenuBar />
          <Terminal frame={frame} />

          <div
            style={{
              position: "absolute",
              top: 0,
              left: "50%",
              translate: "-50% 0",
              overflow: "hidden",
              width: interpolate(frame, [mac.openNotch, mac.panelOpen, mac.closeNotch, mac.notchClosed], [notch.compactWidth, panelWidth, panelWidth, notch.compactWidth], { ...clamp, easing: ease }),
              height: interpolate(frame, [mac.openNotch, mac.panelOpen, mac.typingStart, mac.typingStart + 12, mac.result, mac.resultOpen, mac.closeNotch, mac.notchClosed], [30, 330, 330, 410, 410, 550, 550, 30], { ...clamp, easing: ease }),
              borderRadius: `0 0 ${interpolate(frame, [mac.openNotch, mac.panelOpen, mac.closeNotch, mac.notchClosed], [12, 22, 22, 12], clamp)}px ${interpolate(frame, [mac.openNotch, mac.panelOpen, mac.closeNotch, mac.notchClosed], [12, 22, 22, 12], clamp)}px`,
              background: interpolateColors(frame, [mac.openNotch, mac.openNotch + 5, mac.closeNotch + 3, mac.notchClosed], ["#000000", "#ffffff", "#ffffff", "#000000"]),
              boxShadow: "0 14px 44px rgba(0,0,0,0.6)",
            }}
          >
            <div
              style={{
                position: "absolute",
                top: 0,
                left: "50%",
                translate: "-50% 0",
                width: notch.compactWidth,
                height: notch.height,
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                padding: "0 14px",
                boxSizing: "border-box",
                color: "#c8c8c8",
                opacity: interpolate(frame, [mac.openNotch - 1, mac.openNotch + 3, mac.closeNotch + 6, mac.notchClosed + 3], [1, 0, 0, 1], clamp),
              }}
            >
              <RefynMark size={12} />
              <div style={{ width: 6, height: 6, borderRadius: 6, background: colors.white }} />
            </div>
            <div
              style={{
                position: "absolute",
                top: 0,
                left: "50%",
                translate: "-50% 0",
                width: panelWidth,
                height: "100%",
                opacity: interpolate(frame, [mac.openNotch + 4, mac.openNotch + 12, mac.closeNotch - 2, mac.closeNotch + 2], [0, 1, 1, 0], clamp),
              }}
            >
              <Panel />
            </div>
          </div>

          <div style={{ position: "absolute", top: 0, left: "50%", translate: "-50% 0", width: notch.width, height: notch.height, borderRadius: "0 0 10px 10px", background: colors.black }} />
          <Cursor frame={frame} />
        </div>
      </div>
    </AbsoluteFill>
  );
};
