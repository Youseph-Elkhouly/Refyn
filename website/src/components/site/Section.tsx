import type { ReactNode } from "react";

/** Section labels are written the way Refyn writes section titles in a prompt. */
export function SectionLabel({ children }: { children: ReactNode }) {
  return (
    <p className="font-mono text-[13px] text-muted">
      <span aria-hidden="true">## </span>
      {children}
    </p>
  );
}

export const sectionTitle = "font-display mt-3 max-w-[20ch] text-balance text-[clamp(2.75rem,5.4vw,4.5rem)] leading-[1.04] italic";

export function Section({ id, label, title, children }: { id: string; label: string; title: string; children: ReactNode }) {
  return (
    <section id={id} aria-labelledby={`${id}-title`} className="offscreen-section mx-auto max-w-[1120px] px-5 pt-28 lg:pt-36">
      <div className="reveal mb-10 lg:mb-14">
        <SectionLabel>{label}</SectionLabel>
        <h2 id={`${id}-title`} className={sectionTitle}>
          {title}
        </h2>
      </div>
      {children}
    </section>
  );
}
