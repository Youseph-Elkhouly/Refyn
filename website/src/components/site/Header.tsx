import { RefynMark } from "@/components/refyn/icons";
import { navLinks, site } from "@/lib/site";

export function Header() {
  return (
    <header className="mx-auto flex h-16 max-w-[1320px] items-center justify-between px-5 lg:px-10">
      <a href="#top" className="inline-flex items-center gap-2 rounded-md text-[16px] font-semibold tracking-[-0.01em]">
        <RefynMark size={14} />
        Refyn
      </a>
      <nav aria-label="Sections" className="flex items-center gap-7 text-[14px]">
        {navLinks.map(({ href, label }) => (
          <a key={href} href={href} className="hidden rounded text-muted transition-colors duration-200 hover:text-ink lg:inline">
            {label}
          </a>
        ))}
        <a href={site.downloadUrl} className="rounded font-medium text-ink transition-opacity duration-200 hover:opacity-60">
          Download
        </a>
      </nav>
    </header>
  );
}
