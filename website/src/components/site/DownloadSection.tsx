import { DownloadButton } from "./CallToAction";

const requirements = ["Free to use", "macOS 14 or later", "Apple Silicon", "About 8 GB of free memory recommended", "2.3 GB model download on first setup"];

/** The closing call to action is the notch at full size, inverted: flat top, rounded bottom, hung from a hairline. */
export function DownloadSection() {
  return (
    <section id="download" aria-labelledby="download-title" className="offscreen-section mt-28 border-t border-line px-3 sm:px-5 lg:mt-36">
      <div className="reveal app-light mx-auto max-w-[1120px] rounded-b-[34px] bg-white px-6 pt-20 pb-14 text-center text-black sm:rounded-b-[52px] lg:pt-24 lg:pb-16">
        <h2 id="download-title" className="font-display mx-auto max-w-[14ch] text-balance text-[clamp(3.25rem,7.4vw,6rem)] leading-[1.02] italic">
          Your next prompt starts here.
        </h2>
        <DownloadButton inverted className="mt-9" />
        <ul className="mt-7 flex flex-col gap-1 text-[14px] text-muted lg:flex-row lg:justify-center">
          {requirements.map((requirement, index) => (
            <li key={requirement}>
              {index > 0 && <span className="mx-2 hidden lg:inline" aria-hidden="true">·</span>}
              {requirement}
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
