"use client";

import { useReducedMotion } from "motion/react";
import { useCallback, useEffect, useRef, useState } from "react";

import { demoOutputs, demoRequest, promptToText, type DemoMode } from "@/content/prompts";

export type Route = "compose" | "result";
export type ResultTab = "Prompt" | "Plan";

const total = demoRequest.length;
const generationMs = 1300;
const resultHoldMs = 5200;
const pastedHoldMs = 1800;

/** All the state of the simulated app. Timings are shortened; the output is prewritten. */
export function useRefynDemo({ autoplay = false, isPaused = false }: { autoplay?: boolean; isPaused?: boolean } = {}) {
  const reduced = useReducedMotion() ?? false;
  const [isOpen, setOpen] = useState(false);
  const [hasOpened, setHasOpened] = useState(false);
  const [route, setRoute] = useState<Route>("compose");
  const [typedCount, setTypedCount] = useState(0);
  const [isOptimizing, setOptimizing] = useState(false);
  const [mode, setMode] = useState<DemoMode>("Auto");
  const [outputMode, setOutputMode] = useState<DemoMode>("Auto");
  const [tab, setTab] = useState<ResultTab>("Prompt");
  const [copied, setCopied] = useState(false);
  const [saved, setSaved] = useState(false);
  const [pasted, setPasted] = useState(false);
  const [runId, setRunId] = useState(0);
  const timer = useRef<number | undefined>(undefined);

  const typed = reduced ? total : typedCount;

  const after = useCallback((ms: number, action: () => void) => {
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(action, ms);
  }, []);

  useEffect(() => () => window.clearTimeout(timer.current), []);

  useEffect(() => {
    if (isPaused || !isOpen || route !== "compose" || isOptimizing || typed >= total) return;
    const delay = typed === 0 ? 340 : 20 + (typed % 5) * 7;
    const id = window.setTimeout(() => setTypedCount((count) => count + 1), delay);
    return () => window.clearTimeout(id);
  }, [isPaused, isOpen, route, isOptimizing, typed]);

  const run = useCallback(
    (outputs: DemoMode) => {
      setTypedCount(total);
      setOutputMode(outputs);
      setOptimizing(true);
      after(generationMs, () => {
        setOptimizing(false);
        setRoute("result");
        setTab("Prompt");
        setSaved(false);
        setRunId((id) => id + 1);
      });
    },
    [after],
  );

  useEffect(() => {
    if (!autoplay) return;
    const id = window.setTimeout(
      () => {
        setOpen(true);
        setHasOpened(true);
        if (reduced) setRoute("result");
      },
      reduced ? 0 : 650,
    );
    return () => window.clearTimeout(id);
  }, [autoplay, reduced]);

  useEffect(() => {
    if (!autoplay || isPaused || !isOpen || route !== "compose" || isOptimizing || typed < total) return;
    const id = window.setTimeout(() => run("Auto"), 360);
    return () => window.clearTimeout(id);
  }, [autoplay, isPaused, isOpen, route, isOptimizing, typed, run]);

  const finishCopy = useCallback(() => {
    setCopied(true);
    after(750, () => {
      setOpen(false);
      setCopied(false);
      after(340, () => setPasted(true));
    });
  }, [after]);

  // The autoplaying version keeps going: hold on the result, copy, collapse, paste, then start again.
  useEffect(() => {
    if (!autoplay || reduced || isPaused || !isOpen || route !== "result" || isOptimizing || copied) return;
    const id = window.setTimeout(finishCopy, resultHoldMs);
    return () => window.clearTimeout(id);
  }, [autoplay, reduced, isPaused, isOpen, route, isOptimizing, copied, finishCopy]);

  useEffect(() => {
    if (!autoplay || reduced || isPaused || !pasted) return;
    const id = window.setTimeout(() => {
      setPasted(false);
      setTypedCount(0);
      setRoute("compose");
      setOpen(true);
    }, pastedHoldMs);
    return () => window.clearTimeout(id);
  }, [autoplay, reduced, isPaused, pasted]);

  const open = useCallback(() => {
    setOpen(true);
    setHasOpened(true);
  }, []);

  const close = useCallback(() => setOpen(false), []);

  const output = demoOutputs[outputMode];

  return {
    isOpen,
    hasOpened,
    route,
    typedText: demoRequest.slice(0, typed),
    isTyping: typed < total,
    isOptimizing,
    mode,
    outputMode,
    output,
    tab,
    copied,
    saved,
    pasted,
    runId,
    reduced,
    open,
    close,
    setMode,
    setTab,
    optimize: () => {
      if (typed > 0 || isOpen) run(mode);
    },
    cancel: () => {
      window.clearTimeout(timer.current);
      setOptimizing(false);
    },
    regenerate: () => run(outputMode),
    edit: () => setRoute("compose"),
    save: () => setSaved(true),
    copy: () => {
      navigator.clipboard?.writeText(promptToText(output)).catch(() => undefined);
      finishCopy();
    },
    newPrompt: () => {
      window.clearTimeout(timer.current);
      setTypedCount(0);
      setRoute("compose");
      setOptimizing(false);
      setCopied(false);
      setSaved(false);
      setPasted(false);
    },
    startOver: () => {
      window.clearTimeout(timer.current);
      setOpen(false);
      setHasOpened(false);
      setTypedCount(0);
      setRoute("compose");
      setOptimizing(false);
      setCopied(false);
      setSaved(false);
      setPasted(false);
      setMode("Auto");
    },
  };
}

export type RefynDemo = ReturnType<typeof useRefynDemo>;
