"use client";

import { MacScreen } from "@/components/mac/MacScreen";
import { useRefynDemo } from "@/components/refyn/useRefynDemo";

/** The top of the display, rising out of the fold. Plays once on load, then holds on the finished prompt. */
export function HeroVisual() {
  const demo = useRefynDemo({ autoplay: true });

  return (
    <div
      id="hero-display"
      role="img"
      aria-label="Refyn opened from a MacBook notch, turning the request “my app is slow and buggy, fix it” into a structured debugging prompt."
      className="relative mx-auto mt-12 h-[clamp(450px,62svh,640px)] max-w-[1120px] px-3 [mask-image:linear-gradient(#000_calc(100%-56px),transparent)] sm:px-5 lg:mt-14"
    >
      <div className="relative h-[calc(100%+24px)] rounded-t-[22px] bg-black p-[6px] pb-0 shadow-[0_0_0_1.5px_#3a3a3c] sm:rounded-t-[28px] sm:p-[10px] sm:pb-0">
        <div className="relative h-full overflow-hidden rounded-t-[14px] sm:rounded-t-[18px]">
          <MacScreen demo={demo} isInteractive={false} panelInset={64} />
        </div>
      </div>
    </div>
  );
}
