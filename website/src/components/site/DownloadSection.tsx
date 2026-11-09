import { DownloadButton } from "./CallToAction";

const requirements = ["macOS 14 or later", "Apple Silicon", "About 8 GB of free memory recommended", "2.3 GB model download on first setup"];

/** The closing call to action is the notch at full size: flat top, rounded bottom, hung from a hairline. */
export function DownloadSection() {
  return (
    <section id="download" aria-labelledby="download-title" className="offscreen-section mt-28 border-t border-line px-3 sm:px-6 lg:mt-40 lg:px-10">
      <div className="reveal mx-auto max-w-[1320px] rounded-b-[34px] bg-black px-6 pt-16 pb-14 text-white sm:rounded-b-[52px] sm:px-12 lg:pt-24 lg:pb-20">
        <h2 id="download-title" className="max-w-[12ch] text-[clamp(2.75rem,7.4vw,6.5rem)] leading-[0.98] font-semibold tracking-[-0.042em]">
          Your next prompt starts here.
        </h2>
        <div className="mt-10 flex flex-col gap-6 lg:mt-14 lg:flex-row lg:items-center lg:justify-between">
          <DownloadButton inverted className="self-start" />
          <ul className="flex flex-col gap-1 text-[14px] text-[#a1a1a1] lg:flex-row lg:gap-0">
            {requirements.map((requirement, index) => (
              <li key={requirement}>
                {index > 0 && <span className="mx-2 hidden lg:inline" aria-hidden="true">·</span>}
                {requirement}
              </li>
            ))}
          </ul>
        </div>
      </div>
    </section>
  );
}
