import type { ReactNode } from "react";

import { Comparison } from "@/components/site/Comparison";
import { DemoSection } from "@/components/site/DemoSection";
import { DownloadSection } from "@/components/site/DownloadSection";
import { Features } from "@/components/site/Features";
import { Footer } from "@/components/site/Footer";
import { Header } from "@/components/site/Header";
import { Hero } from "@/components/site/Hero";
import { HowItWorks } from "@/components/site/HowItWorks";
import { RevealObserver } from "@/components/site/RevealObserver";
import { SiteNotch } from "@/components/site/SiteNotch";
import { site } from "@/lib/site";

const structuredData = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: site.name,
  description: site.description,
  applicationCategory: "DeveloperApplication",
  operatingSystem: "macOS 14 or later",
  url: site.url,
};

function Section({ id, title, children }: { id: string; title: ReactNode; children: ReactNode }) {
  return (
    <section id={id} aria-labelledby={`${id}-title`} className="offscreen-section mx-auto max-w-[1320px] px-5 pt-28 lg:px-10 lg:pt-40">
      <h2 id={`${id}-title`} className="reveal mb-10 max-w-[18ch] text-balance text-[clamp(2.75rem,6vw,5.25rem)] leading-[1] font-semibold tracking-[-0.045em] lg:mb-14">
        {title}
      </h2>
      {children}
    </section>
  );
}

export default function Home() {
  return (
    <>
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData) }} />
      <SiteNotch />
      <div id="top">
        <Header />
        <main>
          <Hero />
          <DemoSection />
          <Section id="examples" title="Same request. Far better brief.">
            <div className="reveal">
              <Comparison />
            </div>
          </Section>
          <Section id="features" title="Small enough to forget. Ready when you need it.">
            <Features />
          </Section>
          <Section id="how-it-works" title="Three steps to a better prompt.">
            <HowItWorks />
          </Section>
          <DownloadSection />
        </main>
        <Footer />
      </div>
      <RevealObserver />
    </>
  );
}
