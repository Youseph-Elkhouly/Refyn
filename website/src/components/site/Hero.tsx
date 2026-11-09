import { site } from "@/lib/site";

import { DownloadButton } from "./CallToAction";
import { HeroVisual } from "./HeroVisual";
import { NotchField } from "./NotchField";

export function Hero() {
  return (
    <section aria-labelledby="hero-title" className="relative overflow-x-clip">
      <NotchField targetSelector="#hero-display" />
      <div className="relative mx-auto max-w-[900px] px-5 pt-14 text-center lg:pt-20">
        <p className="font-mono text-[12px] tracking-[0.16em] text-muted uppercase">The prompt optimizer in your notch</p>
        <h1 id="hero-title" className="font-display mt-5 text-[clamp(3.75rem,9vw,7.25rem)] leading-[1.02] italic">
          <span className="block text-muted">Better prompts.</span>
          <span className="block">Completely free.</span>
        </h1>
        <p className="mx-auto mt-6 max-w-[35rem] text-[18px] leading-[1.5] text-secondary">
          <span className="text-ink">Meet Refyn.</span> The free AI prompt optimizer that lives in your Mac&apos;s notch. Turn rough ideas into precise, actionable prompts in seconds.
        </p>
        <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
          <DownloadButton />
          <a
            href="#demo"
            className="inline-flex h-12 items-center justify-center rounded-[12px] border border-[#3a3a3a] bg-black px-5 text-[16px] font-medium whitespace-nowrap transition-[background-color,transform] duration-200 hover:bg-hover active:scale-[0.98]"
          >
            See how it works
          </a>
        </div>
        <p className="mt-4 text-[13px] text-muted">{site.compatibility}</p>
      </div>
      <HeroVisual />
    </section>
  );
}
