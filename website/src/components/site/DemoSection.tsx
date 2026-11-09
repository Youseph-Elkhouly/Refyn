import { NotchDemo } from "./NotchDemo";
import { SectionLabel, sectionTitle } from "./Section";

export function DemoSection() {
  return (
    <section id="demo" aria-labelledby="demo-title" className="overflow-x-clip px-5 pt-20 lg:pt-28">
      <div className="reveal mx-auto mb-11 grid max-w-[1080px] gap-4 lg:mb-14 lg:grid-cols-2 lg:items-end">
        <div>
          <SectionLabel>Demo</SectionLabel>
          <h2 id="demo-title" className={sectionTitle}>
            Try the notch.
          </h2>
        </div>
        <p className="max-w-[25rem] text-[17px] leading-[1.5] text-muted lg:justify-self-end lg:pb-2">
          This is Refyn&apos;s real interface with a prewritten example. Nothing is sent anywhere. In the app, your Mac generates the prompt in a few seconds.
        </p>
      </div>
      <div className="reveal">
        <NotchDemo />
      </div>
    </section>
  );
}
