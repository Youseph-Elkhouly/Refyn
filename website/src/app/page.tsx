import { Comparison } from "@/components/site/Comparison";
import { DemoSection } from "@/components/site/DemoSection";
import { DownloadSection } from "@/components/site/DownloadSection";
import { Features } from "@/components/site/Features";
import { Footer } from "@/components/site/Footer";
import { Header } from "@/components/site/Header";
import { Hero } from "@/components/site/Hero";
import { HowItWorks } from "@/components/site/HowItWorks";
import { RevealObserver } from "@/components/site/RevealObserver";
import { Section } from "@/components/site/Section";
import { site } from "@/lib/site";

const structuredData = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: site.name,
  description: site.description,
  applicationCategory: "DeveloperApplication",
  operatingSystem: "macOS 14 or later",
  url: site.url,
  offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
};

export default function Home() {
  return (
    <>
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData) }} />
      <div id="top">
        <Header />
        <main>
          <Hero />
          <DemoSection />
          <Section id="examples" label="Examples" title="Same request. Far better brief.">
            <div className="reveal">
              <Comparison />
            </div>
          </Section>
          <Section id="features" label="Features" title="Small enough to forget. Ready when you need it.">
            <Features />
          </Section>
          <Section id="how-it-works" label="How it works" title="Three steps to a better prompt.">
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
