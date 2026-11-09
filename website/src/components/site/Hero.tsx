import { site } from "@/lib/site";

import { DownloadButton } from "./CallToAction";
import { HeroVisual } from "./HeroVisual";

export function Hero() {
  return (
    <section aria-labelledby="hero-title" className="overflow-x-clip">
      <div className="mx-auto grid max-w-[1320px] gap-7 px-5 pt-5 pb-9 lg:grid-cols-12 lg:items-end lg:gap-8 lg:px-10 lg:pt-3 lg:pb-11">
        <h1 id="hero-title" className="text-[13.4vw] leading-[0.96] sm:text-[11.5vw] lg:text-[clamp(5rem,9.1vw,8rem)] font-semibold tracking-[-0.042em] lg:col-span-8">
          <span className="block text-muted">Better prompts.</span>
          <span className="block">Better results.</span>
        </h1>
        <div className="lg:col-span-4 lg:pb-2">
          <p className="max-w-[26rem] text-[18px] leading-[1.42] tracking-[-0.012em] text-muted">
            <span className="font-medium text-ink">Meet Refyn.</span> The AI prompt optimizer that lives in your Mac&apos;s notch. Turn rough ideas into precise, actionable prompts in seconds.
          </p>
          <div className="mt-6 flex flex-wrap items-center gap-2.5">
            <DownloadButton />
            <a
              href="#demo"
              className="inline-flex h-12 items-center justify-center rounded-[14px] border border-line px-4 text-[16px] font-medium whitespace-nowrap transition-[background-color,transform] duration-200 hover:bg-surface active:scale-[0.98]"
            >
              See how it works
            </a>
          </div>
          <p className="mt-3.5 text-[13px] text-muted">{site.compatibility}</p>
        </div>
      </div>
      <HeroVisual />
    </section>
  );
}
