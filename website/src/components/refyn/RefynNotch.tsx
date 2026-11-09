"use client";

import * as m from "motion/react-m";
import { useEffect, useRef } from "react";

import {
  compactContentIn,
  compactContentOut,
  instant,
  panelContentIn,
  panelContentOut,
  surfaceClose,
  surfaceColorToNotch,
  surfaceColorToPanel,
  surfaceOpen,
  surfaceShadow,
} from "@/lib/motion";

import { RefynMark } from "./icons";
import { RefynPanel } from "./RefynPanel";
import type { RefynDemo } from "./useRefynDemo";

export type NotchGeometry = {
  notchWidth: number;
  notchHeight: number;
  panelWidth: number;
  maxPanelHeight: number;
};

/** One surface that grows out of the hardware notch: black and compact, or white and expanded. */
export function RefynNotch({ demo, geometry, isInteractive }: { demo: RefynDemo; geometry: NotchGeometry; isInteractive: boolean }) {
  const { notchWidth, notchHeight, panelWidth, maxPanelHeight } = geometry;
  const { isOpen, route, typedText, reduced, close, optimize } = demo;
  const panelRef = useRef<HTMLDivElement>(null);
  const notchButtonRef = useRef<HTMLButtonElement>(null);
  const wasOpen = useRef(false);

  const compactWidth = notchWidth + 96;
  const resultHeight = demo.outputMode === "Basic" ? 330 : 520;
  const contentHeight = route === "result" ? resultHeight : typedText.length > 0 ? 380 : 300;
  const panelHeight = Math.min(contentHeight + notchHeight, maxPanelHeight);
  const pick = <T,>(transition: T) => (reduced ? instant : transition);

  useEffect(() => {
    if (!isInteractive) return;
    if (isOpen) panelRef.current?.focus({ preventScroll: true });
    else if (wasOpen.current && panelRef.current?.contains(document.activeElement)) {
      notchButtonRef.current?.focus({ preventScroll: true });
    }
    wasOpen.current = isOpen;
  }, [isOpen, isInteractive]);

  useEffect(() => {
    if (!isOpen || !isInteractive) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") close();
    };
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [isOpen, isInteractive, close]);

  return (
    <>
      <m.div
        initial={false}
        className="absolute top-0 left-1/2 z-20 -translate-x-1/2 overflow-hidden"
        animate={{
          width: isOpen ? panelWidth : compactWidth,
          height: isOpen ? panelHeight : notchHeight,
          borderBottomLeftRadius: isOpen ? 22 : 12,
          borderBottomRightRadius: isOpen ? 22 : 12,
          backgroundColor: isOpen ? "#ffffff" : "#000000",
          boxShadow: isOpen ? surfaceShadow.panel : surfaceShadow.notch,
        }}
        transition={pick({
          default: isOpen ? surfaceOpen : surfaceClose,
          backgroundColor: isOpen ? surfaceColorToPanel : surfaceColorToNotch,
          boxShadow: isOpen ? surfaceColorToPanel : surfaceColorToNotch,
        })}
      >
        <m.div
          initial={false}
          className="absolute top-0 left-1/2 -translate-x-1/2"
          style={{ width: compactWidth, height: notchHeight, pointerEvents: isOpen ? "none" : "auto" }}
          animate={{ opacity: isOpen ? 0 : 1 }}
          transition={pick(isOpen ? compactContentOut : compactContentIn)}
        >
          {isInteractive ? (
            <button
              ref={notchButtonRef}
              type="button"
              aria-label="Open Refyn"
              aria-expanded={isOpen}
              tabIndex={isOpen ? -1 : 0}
              onClick={demo.open}
              className="on-notch group flex size-full items-center justify-between px-3.5 text-[#a1a1a1] transition-colors duration-200 hover:bg-white/[0.08] hover:text-white"
            >
              <CompactContent isBusy={demo.isOptimizing} />
            </button>
          ) : (
            <div className="flex size-full items-center justify-between px-3.5 text-[#a1a1a1]">
              <CompactContent isBusy={false} />
            </div>
          )}
        </m.div>

        <m.div
          ref={panelRef}
          tabIndex={-1}
          inert={!isOpen || !isInteractive}
          initial={false}
          className="absolute top-0 left-1/2 -translate-x-1/2 outline-none"
          style={{ width: panelWidth, height: panelHeight, paddingTop: notchHeight }}
          animate={{ opacity: isOpen ? 1 : 0 }}
          transition={pick(isOpen ? panelContentIn : panelContentOut)}
          onKeyDown={(event) => {
            if (event.key === "Enter" && (event.metaKey || event.ctrlKey) && route === "compose" && !demo.isOptimizing) optimize();
          }}
        >
          <RefynPanel demo={demo} isInteractive={isInteractive} />
        </m.div>
      </m.div>

      {/* The hardware notch: always on top, the panel slides out from under it. */}
      <div
        aria-hidden="true"
        className="pointer-events-none absolute top-0 left-1/2 z-30 -translate-x-1/2 rounded-b-[10px] bg-black"
        style={{ width: notchWidth, height: notchHeight }}
      >
        <span className="absolute top-1/2 left-1/2 size-[7px] -translate-x-1/2 -translate-y-1/2 rounded-full bg-[#10131a] ring-1 ring-white/[0.06]" />
      </div>

      {isInteractive && isOpen && (
        <button
          type="button"
          aria-label="Collapse Refyn"
          onClick={close}
          className="on-notch absolute top-0 left-1/2 z-40 -translate-x-1/2 rounded-b-[10px]"
          style={{ width: notchWidth, height: notchHeight }}
        />
      )}
    </>
  );
}

function CompactContent({ isBusy }: { isBusy: boolean }) {
  return (
    <>
      <RefynMark size={12} className="transition-transform duration-200 group-hover:scale-110" />
      {isBusy ? (
        <span className="animate-spin-fast size-2.5 rounded-full border-[1.5px] border-white/25 border-t-white motion-reduce:animate-none" />
      ) : (
        <span className="size-1.5 rounded-full bg-white" />
      )}
    </>
  );
}
