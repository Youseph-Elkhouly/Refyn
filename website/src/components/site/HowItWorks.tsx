import type { CSSProperties, ReactNode } from "react";

import { CheckIcon } from "@/components/refyn/icons";
import { Chip, RButton } from "@/components/refyn/primitives";

const step = (ms: number) => ({ "--step": `${ms}ms` }) as CSSProperties;

function PreviewFrame({ children }: { children: ReactNode }) {
  return <div className="flex h-[226px] flex-col overflow-hidden rounded-[18px] border border-line bg-white">{children}</div>;
}

function WritePreview() {
  return (
    <PreviewFrame>
      <div className="flex-1 px-4 pt-4 text-[15px] leading-[22px]">
        <span className="step-type inline-block" style={step(150)}>
          my app is slow and buggy, fix it
        </span>
      </div>
      <div className="flex h-12 items-center justify-end border-t border-line px-3">
        <RButton kind="primary" tabIndex={-1} aria-hidden="true">
          Optimize
        </RButton>
      </div>
    </PreviewFrame>
  );
}

const refinedLines = [
  ["## ", "Objective"],
  ["", "Find what is making the app slow"],
  ["## ", "Investigation"],
  ["1. ", "Reproduce each problem"],
  ["2. ", "Profile before changing code"],
  ["## ", "Verification"],
];

function RefinePreview() {
  return (
    <PreviewFrame>
      <div className="flex h-11 items-center justify-between border-b border-line px-4 text-[12px] text-secondary">
        <span className="step-in" style={step(1100)}>
          Running locally
        </span>
        <span className="step-in" style={step(1250)}>
          <Chip>Qwen3 · on-device</Chip>
        </span>
      </div>
      <div className="flex-1 px-4 pt-3 text-[13px] leading-[23px]">
        {refinedLines.map(([marker, text], index) => (
          <div key={text} className="step-in" style={step(1350 + index * 90)}>
            <span className="text-muted">{marker}</span>
            <span className={marker === "## " ? "font-semibold" : ""}>{text}</span>
          </div>
        ))}
      </div>
    </PreviewFrame>
  );
}

function ShipPreview() {
  return (
    <PreviewFrame>
      <div className="flex h-11 items-center justify-between border-b border-line px-4">
        <span className="text-[12px] text-secondary">For Claude Code</span>
        <span className="step-in inline-flex items-center gap-1 text-[12px] font-medium" style={step(2150)}>
          <CheckIcon size={12} />
          Copied
        </span>
      </div>
      <div className="flex-1 bg-[#141414] p-4 font-mono text-[12px] leading-[20px] text-[#d4d4d4]">
        <div className="text-[#8a8a8a]">Agent ready.</div>
        <div className="step-in mt-2" style={step(2500)}>
          <span className="text-white">&gt;</span> ## Objective
          <div className="pl-3.5">Find what is making the app slow…</div>
          <div className="pl-3.5 text-[#8a8a8a]">[pasted 13 more lines]</div>
        </div>
      </div>
    </PreviewFrame>
  );
}

const steps = [
  { title: "Write anything.", body: "Enter a rough prompt directly into Refyn. Typos and half-thoughts are fine.", preview: <WritePreview /> },
  { title: "Refyn it.", body: "Let the local AI improve clarity, structure, and technical specificity.", preview: <RefinePreview /> },
  { title: "Ship faster.", body: "Copy the optimized prompt into your favorite coding agent.", preview: <ShipPreview /> },
];

export function HowItWorks() {
  return (
    <ol className="reveal grid gap-10 md:grid-cols-3 md:gap-5">
      {steps.map(({ title, body, preview }, index) => (
        <li key={title}>
          {preview}
          <div className="mt-5 flex gap-3">
            <span className="pt-[3px] text-[15px] font-medium text-muted tabular-nums" aria-hidden="true">
              {index + 1}
            </span>
            <div>
              <h3 className="text-[22px] leading-[1.2] font-semibold tracking-[-0.025em]">{title}</h3>
              <p className="mt-1.5 max-w-[22rem] text-[16px] leading-[1.45] tracking-[-0.008em] text-muted">{body}</p>
            </div>
          </div>
        </li>
      ))}
    </ol>
  );
}
