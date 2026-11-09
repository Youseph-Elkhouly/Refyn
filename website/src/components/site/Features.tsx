import type { ReactNode } from "react";

import { BookmarkIcon, CheckIcon, RefynMark } from "@/components/refyn/icons";
import { Chip, KeyHint, Spinner, Waveform } from "@/components/refyn/primitives";

function NotchPreview() {
  return (
    <div className="flex w-full flex-col items-center gap-9 self-start">
      <div className="flex h-[30px] w-[220px] items-center justify-between rounded-b-xl bg-black px-3.5 text-[#a1a1a1] shadow-[0_0_0_1px_#2a2a2a]">
        <RefynMark size={12} />
        <span className="size-1.5 rounded-full bg-white" />
      </div>
      <div className="flex items-center gap-1.5 text-[13px] text-secondary">
        <KeyHint>⌃</KeyHint>
        <KeyHint>⌥</KeyHint>
        <KeyHint>Space</KeyHint>
        <span className="ml-1">from any app</span>
      </div>
    </div>
  );
}

const agents = ["Claude Code", "Codex", "Cursor"];

function AgentsPreview() {
  return (
    <div className="app-light w-[200px] rounded-[10px] bg-white p-1 text-[13px] text-black">
      {agents.map((agent, index) => (
        <div key={agent} className={`flex h-[30px] items-center justify-between rounded-md px-2.5 ${index === 0 ? "bg-hover font-medium" : "text-secondary"}`}>
          {agent}
          {index === 0 && <CheckIcon size={12} />}
        </div>
      ))}
    </div>
  );
}

function LocalPreview() {
  return (
    <div className="app-light flex flex-col items-center gap-2.5 rounded-[10px] bg-white px-5 py-3.5">
      <span className="inline-flex items-center gap-1.5 text-[13px] text-secondary">
        <Spinner />
        Running locally
      </span>
      <Chip>Qwen3 · on-device</Chip>
    </div>
  );
}

const savedPrompts = ["Fix coupon checkout failure", "Split auth into modules", "Add dark theme tokens"];

function SavedPreview() {
  return (
    <div className="app-light w-[min(100%,250px)] rounded-[10px] bg-white text-[13px] text-black">
      {savedPrompts.map((title, index) => (
        <div key={title} className={`flex items-center gap-2.5 px-3 py-[9px] ${index > 0 ? "border-t border-line" : ""}`}>
          <BookmarkIcon size={12} className="shrink-0 text-muted" />
          <span className="truncate">{title}</span>
        </div>
      ))}
    </div>
  );
}

function VoicePreview() {
  return (
    <div className="flex flex-col items-center gap-4">
      <span className="app-light inline-flex items-center gap-2 rounded-full bg-white px-3.5 py-2 text-[12px] text-secondary">
        <Waveform className="text-black" />
        Listening…
      </span>
      <span className="flex items-center gap-1.5 text-[13px] text-secondary">
        Hold <KeyHint>⌃</KeyHint>
        <KeyHint>⌥</KeyHint>
        <KeyHint>D</KeyHint>
      </span>
    </div>
  );
}

function ClarifyPreview() {
  return (
    <div className="app-light w-[min(100%,250px)] rounded-[10px] bg-white p-3 text-black">
      <div className="flex items-baseline justify-between">
        <span className="text-[13px] font-semibold">Needs your input</span>
        <span className="text-[12px] text-muted">2 questions</span>
      </div>
      <div className="mt-2 text-[12px] font-medium text-muted">Which screen feels slow?</div>
      <div className="mt-1 flex h-[30px] items-center rounded-lg border border-line bg-surface px-2.5 text-[13px] text-muted">Your answer (optional)</div>
    </div>
  );
}

const features: { title: string; body: string; preview: ReactNode }[] = [
  {
    title: "One notch. Every prompt.",
    body: "Access prompt optimization directly from your MacBook's notch. On a display without one, Refyn waits at the top center.",
    preview: <NotchPreview />,
  },
  {
    title: "Built for coding agents.",
    body: "Turn vague requests into precise instructions for Codex, Claude Code, and other coding assistants.",
    preview: <AgentsPreview />,
  },
  {
    title: "Local AI optimization.",
    body: "Qwen3 runs on your Mac through MLX. No API keys, no cloud inference, no per-prompt charges, and it works offline after one model download.",
    preview: <LocalPreview />,
  },
  {
    title: "Your prompts, organized.",
    body: "Save the prompts worth keeping and search your history. Add a workspace and notes, and Refyn brings in only the relevant context.",
    preview: <SavedPreview />,
  },
  {
    title: "Voice to prompt.",
    body: "Hold a shortcut and say what you need. Refyn transcribes it on your Mac and leaves it in the editor. Download a speech model once from Settings.",
    preview: <VoicePreview />,
  },
  {
    title: "Asks before it guesses.",
    body: "When a request is missing something important, Refyn asks up to three quick questions instead of inventing the answer.",
    preview: <ClarifyPreview />,
  },
];

export function Features() {
  return (
    <div className="reveal grid gap-px overflow-hidden rounded-[20px] border border-line bg-line md:grid-cols-2 lg:grid-cols-3">
      {features.map(({ title, body, preview }) => (
        <article key={title} className="bg-black p-5 lg:p-6">
          <div className="flex h-[156px] items-center justify-center overflow-hidden rounded-[12px] bg-[#111111] px-4">{preview}</div>
          <h3 className="mt-5 text-[17px] font-semibold">{title}</h3>
          <p className="mt-1.5 text-[15px] leading-[1.5] text-muted">{body}</p>
        </article>
      ))}
    </div>
  );
}
