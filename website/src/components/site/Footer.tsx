import { RefynMark } from "@/components/refyn/icons";
import { site } from "@/lib/site";

export function Footer() {
  return (
    <footer className="mx-auto flex max-w-[1120px] flex-wrap items-center justify-between gap-3 px-5 py-9 text-[14px] text-muted">
      <span className="inline-flex items-center gap-2 font-medium text-ink">
        <RefynMark size={12} />
        Refyn
      </span>
      <span>Your prompts stay on your Mac.</span>
      <a href={site.repoUrl} className="rounded transition-colors duration-200 hover:text-ink">
        GitHub
      </a>
    </footer>
  );
}
