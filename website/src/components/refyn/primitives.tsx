import type { ButtonHTMLAttributes, ReactNode } from "react";

import type { PromptDoc } from "@/content/prompts";

type ButtonKind = "primary" | "secondary" | "ghost";

const buttonKinds: Record<ButtonKind, string> = {
  primary: "bg-black text-white enabled:hover:bg-black/85 enabled:active:bg-black/75 disabled:bg-hover disabled:text-muted",
  secondary: "border border-line bg-white text-black enabled:hover:bg-hover enabled:active:bg-line disabled:text-muted",
  ghost: "text-secondary enabled:hover:bg-hover enabled:hover:text-black enabled:active:bg-line",
};

export function RButton({
  kind = "secondary",
  className = "",
  children,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { kind?: ButtonKind }) {
  return (
    <button
      type="button"
      className={`inline-flex h-7 shrink-0 items-center justify-center gap-1.5 rounded-lg px-3 text-[13px] font-medium whitespace-nowrap transition-colors duration-[120ms] ${buttonKinds[kind]} ${className}`}
      {...props}
    >
      {children}
    </button>
  );
}

export function Segmented<T extends string>({
  options,
  selected,
  onSelect,
  disabledOptions = [],
  label,
}: {
  options: readonly T[];
  selected: T;
  onSelect: (option: T) => void;
  disabledOptions?: readonly T[];
  label: string;
}) {
  return (
    <div role="group" aria-label={label} className="inline-flex shrink-0 gap-0.5 rounded-lg border border-line bg-surface p-0.5">
      {options.map((option) => {
        const isSelected = option === selected;
        const isDisabled = disabledOptions.includes(option);
        return (
          <button
            key={option}
            type="button"
            aria-pressed={isSelected}
            disabled={isDisabled}
            title={isDisabled ? "Pick individual techniques in the app" : undefined}
            onClick={() => onSelect(option)}
            className={`h-[22px] rounded-md border px-2.5 text-[12px] font-medium transition-colors duration-[120ms] ${
              isSelected ? "border-line bg-white text-black" : "border-transparent text-muted enabled:hover:text-secondary"
            } disabled:text-muted/60`}
          >
            {option}
          </button>
        );
      })}
    </div>
  );
}

export function Chip({ children }: { children: ReactNode }) {
  return (
    <span className="inline-flex shrink-0 items-center rounded-full border border-line px-[7px] py-0.5 text-[10.5px] leading-[14px] font-medium whitespace-nowrap text-secondary">
      {children}
    </span>
  );
}

export function KeyHint({ children }: { children: ReactNode }) {
  return (
    <kbd className="inline-flex items-center rounded border border-line px-[5px] py-px font-sans text-[10.5px] leading-[14px] font-medium text-muted">
      {children}
    </kbd>
  );
}

export function Spinner({ size = 12 }: { size?: number }) {
  return (
    <span
      aria-hidden="true"
      className="animate-spin-fast inline-block rounded-full border-[1.5px] border-black/15 border-t-black motion-reduce:animate-none"
      style={{ width: size, height: size }}
    />
  );
}

export function Hairline() {
  return <div aria-hidden="true" className="h-px shrink-0 bg-line" />;
}

export function Waveform({ bars = 14, height = 16, className = "" }: { bars?: number; height?: number; className?: string }) {
  return (
    <span aria-hidden="true" className={`inline-flex items-center gap-0.5 ${className}`} style={{ height }}>
      {Array.from({ length: bars }, (_, index) => (
        <span
          key={index}
          className="wave-bar w-0.5 rounded-full bg-current"
          style={{ height, animationDelay: `${(index * 137) % 620}ms`, animationDuration: `${780 + ((index * 211) % 520)}ms` }}
        />
      ))}
    </span>
  );
}

/** Renders a generated prompt the way it pastes: markdown section titles, numbered or bulleted lines. */
export function PromptView({ doc, animate = false, className = "" }: { doc: PromptDoc; animate?: boolean; className?: string }) {
  let line = 0;
  const lineProps = () => (animate ? { className: "line-in", style: { animationDelay: `${line++ * 26}ms` } } : {});

  return (
    <div className={`space-y-3.5 ${className}`}>
      {doc.map(({ title, items, ordered }) => (
        <section key={title}>
          <h4 {...lineProps()}>
            <span className="text-muted select-none">## </span>
            <span className="font-semibold">{title}</span>
          </h4>
          {items.length === 1 && !ordered ? (
            <p {...lineProps()}>{items[0]}</p>
          ) : (
            <ul>
              {items.map((item, index) => (
                <li key={item} {...lineProps()}>
                  <span className="flex gap-1.5">
                    <span className="shrink-0 text-muted tabular-nums select-none">{ordered ? `${index + 1}.` : "–"}</span>
                    <span>{item}</span>
                  </span>
                </li>
              ))}
            </ul>
          )}
        </section>
      ))}
    </div>
  );
}
