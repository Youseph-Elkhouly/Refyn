"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";

import { ArrowUpIcon } from "@/components/refyn/icons";
import { RefynNotch, type NotchGeometry } from "@/components/refyn/RefynNotch";
import type { RefynDemo } from "@/components/refyn/useRefynDemo";
import { demoOutputs } from "@/content/prompts";

function geometryFor(width: number, height: number, panelInset: number): NotchGeometry {
  const notchWidth = Math.max(124, Math.round((width * 0.136) / 2) * 2);
  const notchHeight = width < 560 ? 26 : 30;
  return {
    notchWidth,
    notchHeight,
    panelWidth: Math.min(640, Math.floor((width - 16) / 2) * 2),
    maxPanelHeight: height - panelInset,
  };
}

/** The display contents. Sizes come from the measured screen so the phone layout is a closer crop, not a smaller Mac. */
export function MacScreen({
  demo,
  isInteractive,
  panelInset = 8,
}: {
  demo: RefynDemo;
  isInteractive: boolean;
  panelInset?: number;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState<{ width: number; height: number } | null>(null);

  useEffect(() => {
    const element = ref.current;
    if (!element) return;
    const observer = new ResizeObserver(([entry]) => {
      setSize({ width: entry.contentRect.width, height: entry.contentRect.height });
    });
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  const geometry = size && geometryFor(size.width, size.height, panelInset);

  return (
    <div
      ref={ref}
      className="absolute inset-0 overflow-hidden bg-[#161616]"
      onPointerDown={(event) => {
        if (isInteractive && demo.isOpen && !(event.target as Element).closest("[data-notch-surface]")) demo.close();
      }}
    >
      <Wallpaper />
      <MenuBar height={geometry?.notchHeight ?? 30} />
      <TerminalWindow isPasted={demo.pasted} />
      {geometry && (
        <div data-notch-surface className="contents">
          <RefynNotch demo={demo} geometry={geometry} isInteractive={isInteractive} />
        </div>
      )}
      {isInteractive && geometry && !demo.hasOpened && (
        <NotchHint top={geometry.notchHeight + 14}>Click the notch</NotchHint>
      )}
    </div>
  );
}

function NotchHint({ top, children }: { top: number; children: ReactNode }) {
  return (
    <div
      className="pointer-events-none absolute left-1/2 z-10 inline-flex -translate-x-1/2 items-center gap-1.5 rounded-full bg-white px-3 py-1.5 text-[12px] font-medium whitespace-nowrap text-black shadow-[0_2px_10px_rgba(0,0,0,0.5)]"
      style={{ top }}
    >
      <ArrowUpIcon size={11} />
      {children}
    </div>
  );
}

function Wallpaper() {
  return (
    <svg aria-hidden="true" className="absolute inset-0 size-full" viewBox="0 0 1000 640" preserveAspectRatio="xMidYMid slice" fill="none">
      <circle cx="780" cy="470" r="330" stroke="#1f1f1f" strokeWidth="58" />
      <circle cx="780" cy="470" r="118" fill="#1f1f1f" />
    </svg>
  );
}

function MenuBar({ height }: { height: number }) {
  return (
    <div aria-hidden="true" className="absolute inset-x-0 top-0 z-10 flex items-center justify-between bg-white/[0.08] px-3.5 text-[12.5px] text-white" style={{ height }}>
      <div className="flex items-center gap-4">
        <span className="font-semibold">Terminal</span>
        <span className="hidden gap-4 lg:flex">
          <span>Shell</span>
          <span>Edit</span>
          <span>View</span>
          <span>Window</span>
          <span>Help</span>
        </span>
      </div>
      <div className="flex items-center gap-3.5">
        <svg width="17" height="12" viewBox="0 0 17 12" fill="none" className="hidden sm:block">
          <path d="M1 4.4a10.6 10.6 0 0 1 15 0M3.5 6.9a7 7 0 0 1 10 0M6 9.3a3.4 3.4 0 0 1 5 0" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" />
        </svg>
        <svg width="24" height="12" viewBox="0 0 24 12" fill="none">
          <rect x="0.5" y="0.5" width="20" height="11" rx="3" stroke="currentColor" opacity="0.5" />
          <rect x="2" y="2" width="14" height="8" rx="1.6" fill="currentColor" />
          <rect x="22" y="4" width="1.5" height="4" rx="0.7" fill="currentColor" opacity="0.5" />
        </svg>
        <span className="tabular-nums">9:41</span>
      </div>
    </div>
  );
}

function TerminalWindow({ isPasted }: { isPasted: boolean }) {
  const [objective] = demoOutputs.Auto;

  return (
    <div
      aria-hidden="true"
      className="absolute bottom-[7%] left-1/2 h-[46%] min-h-[240px] w-[min(92%,760px)] -translate-x-1/2 overflow-hidden rounded-[11px] bg-[#0a0a0a] font-mono text-[12px] leading-[19px] text-[#d4d4d4] shadow-[0_0_0_1px_rgba(255,255,255,0.12),0_22px_60px_rgba(0,0,0,0.6)]"
    >
      <div className="relative flex h-8 items-center gap-2 border-b border-white/[0.07] px-3">
        <span className="size-3 rounded-full bg-white/[0.16]" />
        <span className="size-3 rounded-full bg-white/[0.16]" />
        <span className="size-3 rounded-full bg-white/[0.16]" />
        <span className="absolute inset-x-0 text-center font-sans text-[12px] font-medium text-[#8a8a8a]">storefront-web</span>
      </div>
      <div className="p-3.5">
        <div className="text-[#8a8a8a]">~/storefront-web</div>
        <div>❯ your-coding-agent</div>
        <div className="mt-2.5 text-[#8a8a8a]">Agent ready. What should we work on?</div>
        <div className="mt-2.5">
          {isPasted ? (
            <div className="line-in">
              <div>
                <span className="text-white">&gt;</span> ## {objective.title}
              </div>
              <div className="pl-3.5">{objective.items[0]}</div>
              <div className="pl-3.5 text-[#8a8a8a]">[pasted 13 more lines]</div>
            </div>
          ) : (
            <div>
              <span className="text-white">&gt;</span> <span aria-hidden="true" className="caret" />
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
