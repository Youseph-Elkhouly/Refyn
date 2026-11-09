import type { ReactNode } from "react";

/** A whole laptop: lid, bezel, and the base's thumb notch. Children fill the display. */
export function MacBook({ children }: { children: ReactNode }) {
  return (
    <div className="mx-auto w-full max-w-[1160px]">
      <div className="rounded-t-[20px] bg-black p-[6px] pb-[10px] shadow-[0_0_0_1.5px_#3a3a3c] sm:rounded-t-[26px] sm:p-[10px] sm:pb-[14px]">
        <div className="relative h-[560px] overflow-hidden rounded-t-[12px] lg:h-auto lg:aspect-[16/10] sm:rounded-t-[16px]">{children}</div>
      </div>
      <div aria-hidden="true" className="relative -mx-[3.5%] h-[12px] rounded-b-[14px] bg-[linear-gradient(#4a4a4d,#2a2a2c_55%,#18181a)] sm:h-[17px] sm:rounded-b-[20px]">
        <div className="absolute top-0 left-1/2 h-[6px] w-[15%] -translate-x-1/2 rounded-b-[8px] bg-[linear-gradient(#111112,#2e2e30)] sm:h-[8px]" />
      </div>
    </div>
  );
}
