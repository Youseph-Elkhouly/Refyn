"use client";

import { useEffect, useState } from "react";
import { ArrowDownIcon } from "@/components/refyn/icons";
import { initialDownloadCount } from "@/lib/downloadCount";
import { site } from "@/lib/site";

type DownloadButtonProps = { inverted?: boolean; compact?: boolean; className?: string };

export function DownloadButton({ inverted = false, compact = false, className = "" }: DownloadButtonProps) {
  const [count, setCount] = useState<number | null>(initialDownloadCount);
  const colors = inverted ? "bg-black text-white hover:bg-black/80" : "bg-white text-black hover:bg-white/85";
  const buttonSize = compact
    ? "h-8 rounded-lg px-3 text-[13px]"
    : "h-12 rounded-[12px] px-5 text-[16px]";

  useEffect(() => {
    fetch("/api/downloads", { cache: "no-store" })
      .then(async (response) => {
        if (!response.ok) throw new Error("Download count is not configured");
        const data = (await response.json()) as { count: number };
        setCount(data.count);
      })
      .catch(() => setCount(null));
  }, []);

  function recordDownloadClick() {
    setCount((current) => current === null ? null : current + 1);
    fetch("/api/downloads", { method: "POST", keepalive: true })
      .then(async (response) => {
        if (!response.ok) throw new Error("Download count is not configured");
        const data = (await response.json()) as { count: number };
        setCount((current) => current === null ? data.count : Math.max(current, data.count));
      })
      .catch(() => setCount(null));
  }

  return (
    <span className={`inline-flex items-center gap-3 ${className}`}>
      <a
        href={site.downloadUrl}
        download
        onClick={recordDownloadClick}
        className={`inline-flex items-center justify-center gap-2 ${buttonSize} font-medium whitespace-nowrap transition-[background-color,transform] duration-200 active:scale-[0.98] ${colors}`}
      >
        {!compact && <ArrowDownIcon size={15} />}
        {compact ? "Download" : "Download for macOS"}
      </a>
      <span aria-live="polite" className={`whitespace-nowrap ${compact ? "text-[11px]" : "text-[13px]"} ${inverted ? "text-black/60" : "text-muted"}`}>
        {count === null ? "Count unavailable" : `${count} downloads`}
      </span>
    </span>
  );
}
