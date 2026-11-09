"use client";

import { useId, useRef, useState, type KeyboardEvent } from "react";

import { PromptView } from "@/components/refyn/primitives";
import { examples } from "@/content/prompts";

export function Comparison() {
  const [active, setActive] = useState(0);
  const tabRefs = useRef<(HTMLButtonElement | null)[]>([]);
  const baseId = useId();

  const select = (index: number, moveFocus = false) => {
    setActive(index);
    const tab = tabRefs.current[index];
    tab?.scrollIntoView({ inline: "center", block: "nearest" });
    if (moveFocus) tab?.focus();
  };

  const onKeyDown = (event: KeyboardEvent) => {
    const last = examples.length - 1;
    const next = { ArrowRight: active === last ? 0 : active + 1, ArrowLeft: active === 0 ? last : active - 1, Home: 0, End: last }[event.key];
    if (next === undefined) return;
    event.preventDefault();
    select(next, true);
  };

  return (
    <div>
      <div role="tablist" aria-label="Example category" onKeyDown={onKeyDown} className="no-scrollbar -mx-5 flex gap-1 overflow-x-auto px-5 lg:mx-0 lg:px-0">
        {examples.map((example, index) => {
          const isActive = index === active;
          return (
            <button
              key={example.id}
              ref={(node) => {
                tabRefs.current[index] = node;
              }}
              id={`${baseId}-tab-${example.id}`}
              role="tab"
              type="button"
              aria-selected={isActive}
              aria-controls={`${baseId}-panel-${example.id}`}
              tabIndex={isActive ? 0 : -1}
              onClick={() => select(index)}
              className={`h-9 shrink-0 rounded-[10px] px-3.5 text-[14px] font-medium whitespace-nowrap transition-colors duration-200 ${
                isActive ? "bg-white text-black" : "text-muted hover:bg-hover hover:text-ink"
              }`}
            >
              {example.label}
            </button>
          );
        })}
      </div>

      {/* Panels share one grid cell, so switching categories never moves the page. */}
      <div className="mt-6 grid overflow-hidden rounded-[22px] border border-line">
        {examples.map((example, index) => {
          const isActive = index === active;
          return (
            <div
              key={example.id}
              id={`${baseId}-panel-${example.id}`}
              role="tabpanel"
              aria-labelledby={`${baseId}-tab-${example.id}`}
              className={`col-start-1 row-start-1 grid transition-[opacity,visibility] duration-[220ms] lg:grid-cols-[5fr_7fr] ${isActive ? "visible opacity-100" : "invisible opacity-0"}`}
            >
              <div className="flex flex-col p-6 lg:p-9">
                <h3 className="text-[13px] font-medium text-muted">Before Refyn</h3>
                <p
                  className={`mt-5 font-display text-[clamp(1.875rem,3.1vw,2.625rem)] leading-[1.14] italic transition-transform duration-[250ms] ease-[var(--ease-native)] motion-reduce:transform-none ${isActive ? "" : "translate-y-1.5"}`}
                >
                  {example.before}
                </p>
                <div className="mt-8 lg:mt-auto lg:pt-10">
                  <div className="text-[13px] font-medium text-muted">What Refyn added</div>
                  <ul className="mt-2.5 space-y-1 text-[15px] tracking-[-0.01em]">
                    {example.added.map((item) => (
                      <li key={item}>{item}</li>
                    ))}
                  </ul>
                </div>
              </div>
              <div className="app-light bg-white p-6 text-black lg:p-9">
                <h3 className="text-[13px] font-medium text-muted">After Refyn</h3>
                <PromptView
                  doc={example.after}
                  className={`mt-5 text-[14px] leading-[21px] transition-transform duration-[250ms] ease-[var(--ease-native)] motion-reduce:transform-none ${isActive ? "" : "translate-y-1.5"}`}
                />
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
