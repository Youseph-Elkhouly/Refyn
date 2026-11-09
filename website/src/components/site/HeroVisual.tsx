"use client";

import { MacScreen } from "@/components/mac/MacScreen";
import { useRefynDemo } from "@/components/refyn/useRefynDemo";

/** A close crop of the top of the display. Plays once on load, then holds on the finished prompt. */
export function HeroVisual() {
  const demo = useRefynDemo({ autoplay: true });

  return (
    <div
      role="img"
      aria-label="Refyn opened from a MacBook notch, turning the request “my app is slow and buggy, fix it” into a structured debugging prompt."
      className="mx-3 h-[clamp(430px,calc(100svh-392px),620px)] [mask-image:linear-gradient(#000_calc(100%-48px),transparent)] sm:mx-6 lg:mx-10"
    >
      <div className="relative h-[calc(100%+24px)] rounded-t-[22px] bg-black p-[6px] pb-0 shadow-[0_0_0_1.5px_#c9c9cc] sm:rounded-t-[30px] sm:p-[12px] sm:pb-0">
        <div className="relative h-full overflow-hidden rounded-t-[14px] sm:rounded-t-[18px]">
          <MacScreen demo={demo} isInteractive={false} panelInset={84} />
        </div>
      </div>
    </div>
  );
}
