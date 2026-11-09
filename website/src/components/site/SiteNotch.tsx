"use client";

import { useReducedMotion } from "motion/react";
import * as m from "motion/react-m";
import { useEffect, useRef, useState } from "react";

import { ArrowDownIcon, RefynMark } from "@/components/refyn/icons";
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
import { navLinks, site } from "@/lib/site";

const compact = { width: 112, height: 32 };
const panel = { width: 296, height: 262 };

/** The site's navigation is a small notch: it opens the same way the app does. */
export function SiteNotch() {
  const [isOpen, setOpen] = useState(false);
  const [isDemoInView, setDemoInView] = useState(false);
  const rootRef = useRef<HTMLElement>(null);
  const reduced = useReducedMotion() ?? false;
  const pick = <T,>(transition: T) => (reduced ? instant : transition);

  useEffect(() => {
    const demo = document.getElementById("demo");
    if (!demo) return;
    const observer = new IntersectionObserver(([entry]) => setDemoInView(entry.isIntersecting), {
      rootMargin: "-20% 0px -20% 0px",
    });
    observer.observe(demo);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    if (!isOpen) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") setOpen(false);
    };
    const onPointerDown = (event: PointerEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    };
    document.addEventListener("keydown", onKeyDown);
    document.addEventListener("pointerdown", onPointerDown);
    return () => {
      document.removeEventListener("keydown", onKeyDown);
      document.removeEventListener("pointerdown", onPointerDown);
    };
  }, [isOpen]);

  return (
    <nav
      ref={rootRef}
      aria-label="Site"
      className={`fixed top-0 left-1/2 z-50 -translate-x-1/2 transition-transform duration-[240ms] ease-[var(--ease-native)] ${
        isDemoInView && !isOpen ? "-translate-y-full" : ""
      }`}
    >
      <m.div
        initial={false}
        className="relative overflow-hidden"
        animate={{
          width: isOpen ? panel.width : compact.width,
          height: isOpen ? panel.height : compact.height,
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
        <m.button
          type="button"
          aria-label={isOpen ? "Close menu" : "Open menu"}
          aria-expanded={isOpen}
          onClick={() => setOpen((open) => !open)}
          initial={false}
          animate={{ opacity: isOpen ? 0 : 1 }}
          transition={pick(isOpen ? compactContentOut : compactContentIn)}
          tabIndex={isOpen ? -1 : 0}
          className="on-notch group absolute top-0 left-1/2 flex -translate-x-1/2 items-center justify-between px-3.5 text-[#a1a1a1] transition-colors duration-200 hover:text-white"
          style={{ width: compact.width, height: compact.height, pointerEvents: isOpen ? "none" : "auto" }}
        >
          <RefynMark size={12} className="transition-transform duration-200 group-hover:scale-110" />
          <span className="size-1.5 rounded-full bg-white" />
        </m.button>

        <m.div
          inert={!isOpen}
          initial={false}
          animate={{ opacity: isOpen ? 1 : 0 }}
          transition={pick(isOpen ? panelContentIn : panelContentOut)}
          className="absolute top-0 left-1/2 flex -translate-x-1/2 flex-col p-3"
          style={{ width: panel.width, height: panel.height }}
        >
          <div className="flex h-8 items-center justify-between px-2 text-black">
            <span className="inline-flex items-center gap-[7px] text-[15px] font-semibold">
              <RefynMark size={12} />
              Refyn
            </span>
            <button type="button" onClick={() => setOpen(false)} className="rounded-md px-1.5 py-0.5 text-[12px] font-medium text-secondary transition-colors duration-[120ms] hover:bg-hover hover:text-black">
              Close
            </button>
          </div>
          <div className="mt-1 flex flex-col">
            {navLinks.map(({ href, label }) => (
              <a key={href} href={href} onClick={() => setOpen(false)} className="flex h-9 items-center rounded-lg px-2 text-[14px] text-black transition-colors duration-[120ms] hover:bg-hover">
                {label}
              </a>
            ))}
          </div>
          <a href={site.downloadUrl} className="mt-auto inline-flex h-9 items-center justify-center gap-1.5 rounded-[10px] bg-black text-[13px] font-medium text-white transition-colors duration-[120ms] hover:bg-black/85">
            <ArrowDownIcon size={12} />
            Download for macOS
          </a>
        </m.div>
      </m.div>
    </nav>
  );
}
