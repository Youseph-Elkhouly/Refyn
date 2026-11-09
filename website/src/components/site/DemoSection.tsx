import { NotchDemo } from "./NotchDemo";

export function DemoSection() {
  return (
    <section id="demo" aria-labelledby="demo-title" className="overflow-x-clip px-5 pt-24 lg:px-10 lg:pt-36">
      <div className="reveal mx-auto mb-11 grid max-w-[1160px] gap-4 lg:mb-14 lg:grid-cols-12 lg:items-end">
        <h2 id="demo-title" className="text-[clamp(2.75rem,6vw,5.25rem)] leading-[1] font-semibold tracking-[-0.045em] lg:col-span-7">
          Try the notch.
        </h2>
        <p className="max-w-[25rem] text-[17px] leading-[1.45] tracking-[-0.01em] text-muted lg:col-span-5 lg:justify-self-end lg:pb-1.5">
          This is Refyn&apos;s real interface with a prewritten example. Nothing is sent anywhere. In the app, your Mac generates the prompt in a few seconds.
        </p>
      </div>
      <div className="reveal">
        <NotchDemo />
      </div>
    </section>
  );
}
