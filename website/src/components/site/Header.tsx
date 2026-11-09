import { RefynMark, StarIcon } from "@/components/refyn/icons";
import { navLinks, site } from "@/lib/site";

export function Header() {
  return (
    <header className="sticky top-0 z-50 border-b border-line bg-black">
      <div className="mx-auto grid h-14 max-w-[1120px] grid-cols-[1fr_auto] items-center px-5 lg:grid-cols-[1fr_auto_1fr]">
        <a href="#top" className="inline-flex items-center gap-2 justify-self-start rounded-md text-[15px] font-semibold">
          <RefynMark size={14} />
          Refyn
        </a>
        <nav aria-label="Sections" className="hidden items-center gap-8 text-[14px] lg:flex">
          {navLinks.map(({ href, label }) => (
            <a key={href} href={href} className="rounded text-muted transition-colors duration-200 hover:text-ink">
              {label}
            </a>
          ))}
        </nav>
        <div className="flex items-center gap-2 justify-self-end">
          <a
            href={site.repoUrl}
            className="hidden h-8 items-center gap-1.5 rounded-lg border border-line px-3 text-[13px] font-medium transition-colors duration-200 hover:bg-hover sm:inline-flex"
          >
            <StarIcon size={13} />
            Star on GitHub
          </a>
          <a href={site.downloadUrl} className="inline-flex h-8 items-center rounded-lg bg-white px-3 text-[13px] font-medium text-black transition-colors duration-200 hover:bg-white/85">
            Download
          </a>
        </div>
      </div>
    </header>
  );
}
