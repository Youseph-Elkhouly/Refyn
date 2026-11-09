"use client";

import { MacBook } from "@/components/mac/MacBook";
import { MacScreen } from "@/components/mac/MacScreen";
import { KeyHint } from "@/components/refyn/primitives";
import { useRefynDemo, type RefynDemo } from "@/components/refyn/useRefynDemo";

function statusFor(demo: RefynDemo) {
  if (demo.pasted) return "Pasted into your agent. That's the whole loop.";
  if (demo.isOptimizing) return "Running locally.";
  if (!demo.isOpen) return demo.hasOpened ? "Refyn keeps your work while it's collapsed." : "Click the notch to open Refyn.";
  if (demo.route === "compose") return "Choose Optimize. Try Basic or Advanced to change how much detail you get.";
  return "Choose Copy to send the prompt to your agent.";
}

export function NotchDemo() {
  const demo = useRefynDemo();

  return (
    <div>
      <MacBook>
        <MacScreen demo={demo} isInteractive />
      </MacBook>
      <div className="mx-auto mt-7 flex max-w-[1160px] flex-wrap items-center justify-between gap-x-6 gap-y-3">
        <p aria-live="polite" className="text-[15px] tracking-[-0.01em] text-ink">
          {statusFor(demo)}
        </p>
        <div className="flex items-center gap-2">
          {demo.hasOpened && (
            <button type="button" onClick={demo.startOver} className="h-9 rounded-[10px] px-3 text-[14px] font-medium text-muted transition-colors duration-200 hover:bg-surface hover:text-ink">
              Start over
            </button>
          )}
          <button
            type="button"
            onClick={demo.isOpen ? demo.close : demo.open}
            className="inline-flex h-9 items-center gap-2 rounded-[10px] border border-line px-3 text-[14px] font-medium transition-colors duration-200 hover:bg-surface"
          >
            {demo.isOpen ? "Collapse" : "Open Refyn"}
            {demo.isOpen && <KeyHint>esc</KeyHint>}
          </button>
        </div>
      </div>
    </div>
  );
}
