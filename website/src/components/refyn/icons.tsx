import type { ReactNode, SVGProps } from "react";

function Icon({ children, size = 14, ...props }: SVGProps<SVGSVGElement> & { size?: number; children: ReactNode }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.3"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      {...props}
    >
      {children}
    </svg>
  );
}

type IconProps = { size?: number; className?: string };

export const HistoryIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M2.6 8a5.4 5.4 0 1 0 1.7-3.9L2.6 5.6" />
    <path d="M2.6 2.9v2.7h2.7M8 5.2V8l2 1.3" />
  </Icon>
);

export const NoteIcon = (p: IconProps) => (
  <Icon {...p}>
    <rect x="2.75" y="2.25" width="10.5" height="11.5" rx="2" />
    <path d="M5.5 5.75h5M5.5 8h5M5.5 10.25h3" />
  </Icon>
);

export const BookmarkIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M4 3.25c0-.7.55-1.25 1.25-1.25h5.5c.7 0 1.25.55 1.25 1.25V14L8 11.2 4 14Z" />
  </Icon>
);

export const GearIcon = (p: IconProps) => (
  <Icon {...p}>
    <circle cx="8" cy="8" r="2" />
    <path d="M8 1.75v1.7M8 12.55v1.7M14.25 8h-1.7M3.45 8h-1.7M12.42 3.58l-1.2 1.2M4.78 11.22l-1.2 1.2M12.42 12.42l-1.2-1.2M4.78 4.78l-1.2-1.2" />
  </Icon>
);

export const MicIcon = (p: IconProps) => (
  <Icon {...p}>
    <rect x="5.75" y="1.75" width="4.5" height="8" rx="2.25" />
    <path d="M3.5 7.75a4.5 4.5 0 0 0 9 0M8 12.25v2" />
  </Icon>
);

export const CopyIcon = (p: IconProps) => (
  <Icon {...p}>
    <rect x="5.25" y="5.25" width="8.5" height="8.5" rx="1.75" />
    <path d="M10.75 5.25V3.5c0-.7-.55-1.25-1.25-1.25h-6c-.7 0-1.25.55-1.25 1.25v6c0 .7.55 1.25 1.25 1.25h1.75" />
  </Icon>
);

export const RefreshIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M13.4 8a5.4 5.4 0 1 1-1.7-3.9l1.7 1.5" />
    <path d="M13.4 2.9v2.7h-2.7" />
  </Icon>
);

export const PencilIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="m10.6 2.9 2.5 2.5-7.9 7.9-3.2.7.7-3.2Z" />
  </Icon>
);

export const PlusIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M8 3v10M3 8h10" />
  </Icon>
);

export const StarIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="m8 2 1.85 3.75 4.15.6-3 2.92.7 4.13L8 11.45 4.3 13.4l.7-4.13-3-2.92 4.15-.6Z" />
  </Icon>
);

export const CheckIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="m3 8.5 3.25 3.25L13 4.75" />
  </Icon>
);

export const XIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="m4 4 8 8M12 4l-8 8" />
  </Icon>
);

export const UpDownIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="m5 6 3-3 3 3M5 10l3 3 3-3" />
  </Icon>
);

export const ArrowDownIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M8 2.5v11M3.5 9 8 13.5 12.5 9" />
  </Icon>
);

export const ArrowUpIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M8 13.5v-11M3.5 7 8 2.5 12.5 7" />
  </Icon>
);

/** The Refyn symbol: a ring around a solid core. */
export function RefynMark({ size = 12, className }: IconProps) {
  const stroke = Math.max(1.2, size / 9);
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} fill="none" aria-hidden="true" className={className}>
      <circle cx={size / 2} cy={size / 2} r={size / 2 - stroke / 2} stroke="currentColor" strokeWidth={stroke} />
      <circle cx={size / 2} cy={size / 2} r={size * 0.18} fill="currentColor" />
    </svg>
  );
}
