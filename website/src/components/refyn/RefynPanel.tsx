"use client";

import { demoPlan, type DemoMode } from "@/content/prompts";

import { BookmarkIcon, CheckIcon, CopyIcon, GearIcon, HistoryIcon, MicIcon, NoteIcon, PencilIcon, PlusIcon, RefreshIcon, RefynMark, UpDownIcon, XIcon } from "./icons";
import { Chip, Hairline, KeyHint, PromptView, RButton, Segmented, Spinner } from "./primitives";
import type { RefynDemo, ResultTab } from "./useRefynDemo";

const modes = ["Auto", "Basic", "Advanced", "Custom"] as const;
const tabs: readonly ResultTab[] = ["Prompt", "Plan"];

/** The expanded app, laid out from the same measurements as ExpandedPanelView, ComposerView and ResultView. */
export function RefynPanel({ demo, isInteractive }: { demo: RefynDemo; isInteractive: boolean }) {
  return (
    <div className="app-light @container flex h-full flex-col text-black">
      <header className="flex h-11 shrink-0 items-center gap-2 px-3.5">
        <span className="inline-flex items-center gap-[7px] text-[15px] font-semibold">
          <RefynMark size={12} />
          Refyn
        </span>
        <span aria-hidden="true" className="h-3.5 w-px bg-line" />
        <span className="inline-flex items-center gap-[5px] px-1.5 text-[14px] text-secondary">
          storefront-web
          <UpDownIcon size={9} />
        </span>
        <span aria-hidden="true" className="ml-auto hidden items-center text-secondary @[440px]:flex">
          {[HistoryIcon, NoteIcon, BookmarkIcon, GearIcon].map((Icon, index) => (
            <span key={index} className="grid size-7 place-items-center">
              <Icon size={14} />
            </span>
          ))}
        </span>
      </header>
      <Hairline />
      <div key={demo.route} className="line-in flex min-h-0 flex-1 flex-col">
        {demo.route === "compose" ? <Composer demo={demo} /> : <Result demo={demo} isInteractive={isInteractive} />}
      </div>
    </div>
  );
}

function Composer({ demo }: { demo: RefynDemo }) {
  const isEmpty = demo.typedText.length === 0;

  return (
    <>
      <div className="min-h-0 flex-1 px-5 py-3.5 text-[16px] leading-[23px]" aria-label="Example request">
        {isEmpty ? <span className="text-secondary">What are you working on?</span> : demo.typedText}
        {!demo.isOptimizing && <span aria-hidden="true" className="caret" />}
      </div>
      <Hairline />
      <div className="flex items-center gap-2 px-3.5 py-2.5">
        <span aria-hidden="true" className="hidden size-7 place-items-center text-secondary @[420px]:grid">
          <MicIcon size={14} />
        </span>
        <Segmented<(typeof modes)[number]>
          label="Prompt mode"
          options={modes}
          selected={demo.mode}
          disabledOptions={["Custom"]}
          onSelect={(mode) => demo.setMode(mode as DemoMode)}
        />
        <span className="ml-auto" />
        {demo.isOptimizing && (
          <span className="hidden items-center gap-1 text-[12px] text-secondary @[480px]:inline-flex">
            <Spinner />
            Running locally
          </span>
        )}
        <span className="hidden @[540px]:inline-flex">
          <KeyHint>⌘↩</KeyHint>
        </span>
        {demo.isOptimizing ? (
          <RButton kind="primary" onClick={demo.cancel}>
            <XIcon size={11} />
            Cancel
          </RButton>
        ) : (
          <RButton kind="primary" disabled={demo.typedText.length === 0} onClick={demo.optimize}>
            Optimize
          </RButton>
        )}
      </div>
      <div className="flex justify-between gap-3 px-4 pb-2.5 text-[12px] text-muted">
        <span>148 components in context</span>
        <span className="hidden @[540px]:inline">⌃⌥Space toggle · hold ⌃⌥D to dictate</span>
      </div>
    </>
  );
}

function Result({ demo, isInteractive }: { demo: RefynDemo; isInteractive: boolean }) {
  return (
    <>
      <div className="flex items-start gap-3 px-[18px] py-3">
        <div className="min-w-0">
          <div className="text-[12px] font-medium text-muted">Your request</div>
          <div className="mt-[3px] truncate text-[14px] text-secondary">{demo.typedText}</div>
        </div>
        <RButton kind="ghost" className="ml-auto" onClick={demo.edit}>
          <PencilIcon size={11} />
          Edit
        </RButton>
      </div>
      <Hairline />
      <div className="flex items-center gap-2 px-[18px] py-2.5">
        <Segmented label="Result view" options={tabs} selected={demo.tab} onSelect={demo.setTab} />
        <span className="ml-auto" />
        <Chip>Qwen3 · on-device</Chip>
        <span className="hidden @[420px]:inline-flex">
          <Chip>bugfix</Chip>
        </span>
      </div>
      <div className="relative min-h-0 flex-1">
        <div
          tabIndex={isInteractive ? 0 : undefined}
          aria-label="Optimized prompt"
          className={`h-full overflow-y-auto overscroll-contain px-[18px] pb-3 text-[13px] leading-[19px] transition-opacity duration-200 ${demo.isOptimizing ? "opacity-35" : ""}`}
        >
          {demo.tab === "Prompt" ? (
            <PromptView key={demo.runId} doc={demo.output} animate />
          ) : (
            <div className="space-y-4 text-[14px] leading-5">
              {demoPlan.map((row) => (
                <div key={row.label}>
                  <div className="mb-1 text-[12px] font-medium text-muted">{row.label}</div>
                  {row.items.map((item) => (
                    <p key={item}>{item}</p>
                  ))}
                </div>
              ))}
            </div>
          )}
        </div>
        {demo.isOptimizing && (
          <div className="absolute inset-0 flex flex-col items-center justify-center gap-3 text-[12px] text-secondary">
            <Spinner size={16} />
            Regenerating…
          </div>
        )}
      </div>
      <Hairline />
      <div className="flex items-center gap-2 px-[18px] py-2.5">
        <RButton kind="primary" onClick={demo.copy}>
          {demo.copied ? <CheckIcon size={12} /> : <CopyIcon size={12} />}
          {demo.copied ? "Copied" : "Copy"}
        </RButton>
        <RButton onClick={demo.save} disabled={demo.saved}>
          {demo.saved ? <CheckIcon size={12} /> : <BookmarkIcon size={12} />}
          {demo.saved ? "Saved" : "Save"}
        </RButton>
        <RButton onClick={demo.regenerate} disabled={demo.isOptimizing} aria-label="Regenerate">
          <RefreshIcon size={12} />
          <span className="hidden @[440px]:inline">Regenerate</span>
        </RButton>
        <span className="ml-auto hidden text-[12px] text-secondary @[520px]:inline">For Claude Code</span>
        <button
          type="button"
          aria-label="New prompt"
          title="New prompt"
          onClick={demo.newPrompt}
          className="ml-auto grid size-7 place-items-center rounded-lg text-secondary transition-colors duration-[120ms] hover:bg-hover hover:text-black @[520px]:ml-0"
        >
          <PlusIcon size={13} />
        </button>
      </div>
    </>
  );
}
