import { ArrowDownIcon } from "@/components/refyn/icons";
import { site } from "@/lib/site";

export function DownloadButton({ inverted = false, className = "" }: { inverted?: boolean; className?: string }) {
  const colors = inverted ? "bg-black text-white hover:bg-black/80" : "bg-white text-black hover:bg-white/85";
  return (
    <a
      href={site.downloadUrl}
      className={`inline-flex h-12 items-center justify-center gap-2 rounded-[12px] px-5 text-[16px] font-medium whitespace-nowrap transition-[background-color,transform] duration-200 active:scale-[0.98] ${colors} ${className}`}
    >
      <ArrowDownIcon size={15} />
      Download for macOS
    </a>
  );
}
