import type { CSSProperties, ReactNode } from "react";
import { interpolate, useCurrentFrame } from "remotion";

import { BookmarkIcon, CheckIcon, CopyIcon, GearIcon, HistoryIcon, MicIcon, NoteIcon, PencilIcon, PlusIcon, RefreshIcon, RefynMark, UpDownIcon, XIcon } from "./icons";
import { clamp, colors, fonts } from "./theme";
import { mac, request } from "./timeline";

const hairline: CSSProperties = { height: 1, background: colors.appLine, flexShrink: 0 };

const Button = ({ children, primary, active }: { children: ReactNode; primary?: boolean; active?: boolean }) => (
  <div
    style={{
      height: 28,
      padding: "0 12px",
      borderRadius: 8,
      display: "flex",
      alignItems: "center",
      gap: 6,
      fontSize: 13,
      fontWeight: 500,
      whiteSpace: "nowrap",
      color: primary ? colors.white : colors.black,
      background: primary ? (active ? "#3a3a3a" : colors.black) : colors.white,
      border: primary ? undefined : `1px solid ${colors.appLine}`,
    }}
  >
    {children}
  </div>
);

const Segmented = ({ options, selected }: { options: string[]; selected: string }) => (
  <div style={{ display: "flex", gap: 2, padding: 2, borderRadius: 8, background: colors.appSurface, border: `1px solid ${colors.appLine}` }}>
    {options.map((option) => (
      <div
        key={option}
        style={{
          height: 22,
          lineHeight: "20px",
          padding: "0 10px",
          borderRadius: 6,
          fontSize: 12,
          fontWeight: 500,
          boxSizing: "border-box",
          color: option === selected ? colors.black : colors.appMuted,
          background: option === selected ? colors.white : "transparent",
          border: `1px solid ${option === selected ? colors.appLine : "transparent"}`,
        }}
      >
        {option}
      </div>
    ))}
  </div>
);

const Chip = ({ children }: { children: ReactNode }) => (
  <div style={{ padding: "2px 7px", borderRadius: 99, border: `1px solid ${colors.appLine}`, fontSize: 10.5, lineHeight: "14px", fontWeight: 500, color: colors.appSecondary }}>{children}</div>
);

const Spinner = ({ frame }: { frame: number }) => (
  <div style={{ width: 12, height: 12, borderRadius: 12, border: "1.5px solid rgba(0,0,0,0.15)", borderTopColor: colors.black, boxSizing: "border-box", rotate: `${frame * 16}deg` }} />
);

const Header = () => (
  <div style={{ height: 44, display: "flex", alignItems: "center", gap: 8, padding: "0 14px", flexShrink: 0 }}>
    <RefynMark size={12} />
    <div style={{ fontSize: 15, fontWeight: 600 }}>Refyn</div>
    <div style={{ width: 1, height: 14, background: colors.appLine, margin: "0 2px" }} />
    <div style={{ display: "flex", alignItems: "center", gap: 5, fontSize: 14, color: colors.appSecondary, padding: "0 6px" }}>
      storefront-web
      <UpDownIcon size={9} />
    </div>
    <div style={{ marginLeft: "auto", display: "flex", color: colors.appSecondary }}>
      {[HistoryIcon, NoteIcon, BookmarkIcon, GearIcon].map((Icon, index) => (
        <div key={index} style={{ width: 28, height: 28, display: "grid", placeItems: "center" }}>
          <Icon size={14} />
        </div>
      ))}
    </div>
  </div>
);

const Composer = ({ frame }: { frame: number }) => {
  const typed = request.slice(0, Math.floor(interpolate(frame, [mac.typingStart, mac.typingEnd], [0, request.length], clamp)));
  const isRunning = frame >= mac.clickOptimize;
  const caretOn = !isRunning && Math.floor(frame / 16) % 2 === 0;

  return (
    <>
      <div style={{ flex: 1, padding: "14px 20px", fontSize: 16, lineHeight: "23px" }}>
        {typed ? typed : <span style={{ color: colors.appSecondary }}>What are you working on?</span>}
        <span style={{ display: "inline-block", width: 1.5, height: 18, marginLeft: 1, verticalAlign: -3, background: colors.black, opacity: caretOn ? 1 : 0 }} />
      </div>
      <div style={hairline} />
      <div style={{ display: "flex", alignItems: "center", gap: 8, padding: "10px 14px" }}>
        <div style={{ width: 28, height: 28, display: "grid", placeItems: "center", color: colors.appSecondary }}>
          <MicIcon size={14} />
        </div>
        <Segmented options={["Auto", "Basic", "Advanced", "Custom"]} selected="Auto" />
        <div style={{ marginLeft: "auto", display: "flex", alignItems: "center", gap: 6, fontSize: 12, color: colors.appSecondary, opacity: isRunning ? 1 : 0 }}>
          <Spinner frame={frame} />
          Running locally
        </div>
        {isRunning ? (
          <Button primary>
            <XIcon size={11} />
            Cancel
          </Button>
        ) : (
          <Button primary active={frame >= mac.clickOptimize - 4}>
            Optimize
          </Button>
        )}
      </div>
      <div style={{ display: "flex", justifyContent: "space-between", padding: "0 16px 10px", fontSize: 12, color: colors.appMuted }}>
        <span>148 components in context</span>
        <span>⌃⌥Space toggle · hold ⌃⌥D to dictate</span>
      </div>
    </>
  );
};

type PromptLine = { kind: "title" | "text" | "item"; marker?: string; text: string };

const promptLines: PromptLine[] = [
  { kind: "title", text: "Objective" },
  { kind: "text", text: "Find what is making the app slow and buggy, then fix the causes you can confirm." },
  { kind: "title", text: "Investigation" },
  { kind: "item", marker: "1.", text: "Reproduce the slowness and each bug, and write down the exact steps." },
  { kind: "item", marker: "2.", text: "Profile the slowest flows before changing code, and record a baseline." },
  { kind: "item", marker: "3.", text: "Check logs and failing tests for errors that explain the bugs." },
  { kind: "item", marker: "4.", text: "Rank findings by user impact and name the root cause of each." },
  { kind: "title", text: "Constraints" },
  { kind: "item", marker: "–", text: "Only change code tied to a confirmed cause." },
  { kind: "item", marker: "–", text: "Keep public APIs and existing behavior unless a bug requires otherwise." },
  { kind: "item", marker: "–", text: "Ask before adding a dependency or running a migration." },
  { kind: "title", text: "Verification" },
  { kind: "item", marker: "–", text: "Re-run the baseline and report before and after numbers." },
  { kind: "item", marker: "–", text: "Add a regression test for every bug you fix." },
  { kind: "item", marker: "–", text: "Run the full test suite and report the result." },
];

const Result = ({ frame }: { frame: number }) => {
  const isCopied = frame >= mac.clickCopy;

  return (
    <>
      <div style={{ display: "flex", alignItems: "flex-start", padding: "12px 18px" }}>
        <div>
          <div style={{ fontSize: 12, fontWeight: 500, color: colors.appMuted }}>Your request</div>
          <div style={{ fontSize: 14, marginTop: 3, color: colors.appSecondary }}>{request}</div>
        </div>
        <div style={{ marginLeft: "auto", display: "flex", alignItems: "center", gap: 6, fontSize: 13, fontWeight: 500, color: colors.appSecondary, height: 28, padding: "0 12px" }}>
          <PencilIcon size={11} />
          Edit
        </div>
      </div>
      <div style={hairline} />
      <div style={{ display: "flex", alignItems: "center", gap: 8, padding: "10px 18px" }}>
        <Segmented options={["Prompt", "Plan"]} selected="Prompt" />
        <div style={{ marginLeft: "auto" }} />
        <Chip>Qwen3 · on-device</Chip>
        <Chip>bugfix</Chip>
      </div>
      <div style={{ flex: 1, minHeight: 0, overflow: "hidden", padding: "0 18px" }}>
        <div
          style={{
            fontSize: 13,
            lineHeight: "19px",
            translate: `0px ${interpolate(frame, [mac.scrollStart, mac.scrollEnd], [0, -22], { ...clamp })}px`,
          }}
        >
          {promptLines.map((line, index) => {
            const start = mac.result + 6 + index * 1.4;
            return (
              <div
                key={line.text}
                style={{
                  display: "flex",
                  gap: 6,
                  marginTop: line.kind === "title" && index > 0 ? 14 : 0,
                  opacity: interpolate(frame, [start, start + 7], [0, 1], clamp),
                  translate: `0px ${interpolate(frame, [start, start + 7], [5, 0], clamp)}px`,
                }}
              >
                {line.kind === "title" && (
                  <div>
                    <span style={{ color: colors.appMuted }}>## </span>
                    <span style={{ fontWeight: 600 }}>{line.text}</span>
                  </div>
                )}
                {line.kind === "text" && <div>{line.text}</div>}
                {line.kind === "item" && (
                  <>
                    <div style={{ color: colors.appMuted }}>{line.marker}</div>
                    <div>{line.text}</div>
                  </>
                )}
              </div>
            );
          })}
        </div>
      </div>
      <div style={hairline} />
      <div style={{ display: "flex", alignItems: "center", gap: 8, padding: "10px 18px" }}>
        <Button primary active={frame >= mac.clickCopy - 4 && frame < mac.clickCopy + 3}>
          {isCopied ? <CheckIcon size={12} /> : <CopyIcon size={12} />}
          {isCopied ? "Copied" : "Copy"}
        </Button>
        <Button>
          <BookmarkIcon size={12} />
          Save
        </Button>
        <Button>
          <RefreshIcon size={12} />
          Regenerate
        </Button>
        <div style={{ marginLeft: "auto", fontSize: 12, color: colors.appSecondary }}>For Claude Code</div>
        <div style={{ width: 28, height: 28, display: "grid", placeItems: "center", color: colors.appSecondary }}>
          <PlusIcon size={13} />
        </div>
      </div>
    </>
  );
};

/** Refyn's expanded panel, driven entirely by the current frame. */
export const Panel = () => {
  const frame = useCurrentFrame();
  const showResult = frame >= mac.result - 3;

  return (
    <div style={{ width: "100%", height: "100%", display: "flex", flexDirection: "column", paddingTop: 30, boxSizing: "border-box", color: colors.black, fontFamily: fonts.sans }}>
      <Header />
      <div style={hairline} />
      <div
        style={{
          flex: 1,
          minHeight: 0,
          display: "flex",
          flexDirection: "column",
          opacity: interpolate(frame, [mac.result - 7, mac.result - 3, mac.result - 2, mac.result + 4], [1, 0, 0, 1], clamp),
        }}
      >
        {showResult ? <Result frame={frame} /> : <Composer frame={frame} />}
      </div>
    </div>
  );
};
