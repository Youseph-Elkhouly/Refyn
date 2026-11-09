import type { ReactNode } from "react";

import { BookmarkIcon, CheckIcon, RefynMark } from "@/components/refyn/icons";
import { Chip, KeyHint, Spinner, Waveform } from "@/components/refyn/primitives";

function Tile({ children }: { children: ReactNode }) {
  return <div className="flex h-[176px] items-center justify-center overflow-hidden rounded-[18px] bg-surface">{children}</div>;
}

function NotchPreview() {
  return (
    <div className="flex flex-col items-center gap-5 self-start">
      <div className="flex h-[30px] w-[230px] items-center justify-between rounded-b-xl bg-black px-3.5 text-[#a1a1a1]">
        <RefynMark size={12} />
        <span className="size-1.5 rounded-full bg-white" />
      </div>
      <div className="mt-5 flex items-center gap-1.5 text-[13px] text-secondary">
        <KeyHint>⌃</KeyHint>
        <KeyHint>⌥</KeyHint>
        <KeyHint>Space</KeyHint>
        <span className="ml-1">from any app</span>
      </div>
    </div>
  );
}

const agents = ["Claude Code", "Codex", "Cursor", "T3 Code"];

function AgentsPreview() {
  return (
    <div className="w-[210px] rounded-[10px] border border-line bg-white p-1 text-[13px] shadow-[0_6px_18px_rgba(0,0,0,0.07)]">
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
    <div className="flex flex-col items-center gap-3">
      <span className="inline-flex items-center gap-1.5 text-[13px] text-secondary">
        <Spinner />
        Running locally
      </span>
      <Chip>Qwen3 · on-device</Chip>
    </div>
  );
}

const savedPrompts = [
  ["Fix coupon checkout failure", "storefront-web"],
  ["Split auth into modules", "api-server"],
  ["Add dark theme tokens", "storefront-web"],
];

function SavedPreview() {
  return (
    <div className="w-[min(100%,280px)] rounded-[10px] border border-line bg-white text-[13px] shadow-[0_6px_18px_rgba(0,0,0,0.07)]">
      {savedPrompts.map(([title, workspace], index) => (
        <div key={title} className={`flex items-center gap-2.5 px-3 py-[9px] ${index > 0 ? "border-t border-line" : ""}`}>
          <BookmarkIcon size={12} className="shrink-0 text-muted" />
          <span className="min-w-0 flex-1 truncate">{title}</span>
          <span className="hidden text-[12px] text-muted min-[400px]:inline">{workspace}</span>
        </div>
      ))}
    </div>
  );
}

function VoicePreview() {
  return (
    <div className="flex flex-col items-center gap-4">
      <span className="inline-flex items-center gap-2 rounded-full border border-line bg-white px-3 py-1.5 text-[12px] text-secondary">
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

const features = [
  {
    title: "One notch. Every prompt.",
    body: "Refyn sits in your MacBook's notch and opens over whatever you're working in. No window to find, no tab to switch to. On a display without a notch, it waits at the top center.",
    preview: <NotchPreview />,
  },
  {
    title: "Built for coding agents.",
    body: "Turn vague requests into precise instructions for Claude Code, Codex, and other coding assistants. When a request is missing something, Refyn asks up to three quick questions instead of guessing.",
    preview: <AgentsPreview />,
  },
  {
    title: "Local AI optimization.",
    body: "Qwen3 runs on your Mac through MLX. There are no API keys, cloud inference requests, or per-prompt charges, and after one model download it works offline.",
    preview: <LocalPreview />,
  },
  {
    title: "Your prompts, organized.",
    body: "Save the prompts worth keeping and search your history. Add a workspace and notes, and Refyn brings only the relevant context into each prompt.",
    preview: <SavedPreview />,
  },
  {
    title: "Voice to prompt.",
    body: "Hold a shortcut and say what you need. Refyn transcribes it on your Mac and leaves the text in the editor, ready for you to optimize. Download a speech model once from Settings.",
    preview: <VoicePreview />,
  },
];

export function Features() {
  return (
    <div>
      {features.map(({ title, body, preview }) => (
        <article key={title} className="reveal grid gap-6 border-t border-line py-9 lg:grid-cols-12 lg:items-center lg:gap-8 lg:py-11">
          <h3 className="text-[clamp(2rem,3.4vw,3rem)] leading-[1.04] font-semibold tracking-[-0.04em] lg:col-span-5">{title}</h3>
          <p className="max-w-[28rem] text-[16px] leading-[1.5] tracking-[-0.008em] text-muted lg:col-span-3">{body}</p>
          <div className="lg:col-span-4">
            <Tile>{preview}</Tile>
          </div>
        </article>
      ))}
    </div>
  );
}
