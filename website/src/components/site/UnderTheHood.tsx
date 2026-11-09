const stages = [
  {
    title: "Read the request",
    body: "Refyn works out the intent and task type. If something important is missing, it asks up to three quick questions.",
  },
  {
    title: "Gather context",
    body: "From the workspace you choose, it pulls only relevant component summaries, symbols, paths, and notes. Never whole files, and never secrets.",
  },
  {
    title: "Generate with Qwen3",
    body: "Small requests are handled instantly by local rules. The rest go to Qwen3, running on your Mac through MLX, which drafts a structured plan.",
    isModel: true,
  },
  {
    title: "Check the work",
    body: "Code references it can't confirm are dropped, and unsupported names, paths, and numbers are caught. If a plan fails, built-in rules take over and Refyn tells you.",
  },
  {
    title: "Write the prompt",
    body: "Refyn composes the final prompt on your Mac, ready to copy into your agent or save for later.",
  },
];

const specs = [
  { label: "Main model", value: "Qwen3 4B · 4-bit" },
  { label: "Runs on", value: "MLX · Apple Silicon" },
  { label: "One-time download", value: "2.3 GB" },
  { label: "Optional fast model", value: "Qwen3 1.7B · about 1 GB" },
  { label: "Cost per prompt", value: "Nothing" },
];

export function UnderTheHood() {
  return (
    <div id="pipeline" className="reveal mt-24 lg:mt-32">
      <h3 className="font-display max-w-[20ch] text-balance text-[clamp(2.25rem,4vw,3.25rem)] leading-[1.06] italic">What happens when you press Optimize.</h3>
      <p className="mt-4 max-w-[36rem] text-[17px] leading-[1.5] text-muted">
        Every step runs on your Mac. There are no API keys and no cloud inference. Refyn only goes online to download the models.
      </p>

      <div className="mt-9 overflow-hidden rounded-[20px] border border-line">
        <div className="flex h-11 items-center justify-between border-b border-line px-5 font-mono text-[12px] text-muted">
          <span>On your Mac</span>
          <span>Works offline after setup</span>
        </div>
        <ol className="grid gap-px bg-line lg:grid-cols-5">
          {stages.map(({ title, body, isModel }, index) => (
            <li key={title} className={isModel ? "app-light bg-white p-5 text-black" : "bg-black p-5"}>
              <span aria-hidden="true" className="font-mono text-[12px] text-muted">
                {index + 1}
              </span>
              <h4 className="mt-3 text-[16px] font-semibold">{title}</h4>
              <p className="mt-1.5 text-[14px] leading-[1.5] text-muted">{body}</p>
            </li>
          ))}
        </ol>
        <dl className="grid grid-cols-2 gap-px border-t border-line bg-line lg:grid-cols-5">
          {specs.map(({ label, value }, index) => (
            <div key={label} className={`bg-black p-5 ${index === specs.length - 1 ? "col-span-2 lg:col-span-1" : ""}`}>
              <dt className="text-[12px] text-muted">{label}</dt>
              <dd className="mt-1 text-[15px] font-medium">{value}</dd>
            </div>
          ))}
        </dl>
      </div>
    </div>
  );
}
