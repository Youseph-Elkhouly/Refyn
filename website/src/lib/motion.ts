// Mirrors Theme.Motion in the macOS app, so the notch on this page moves the way the real one does.
// The surface uses springs because a spring keeps its velocity when it is reversed mid-flight.

export const surfaceOpen = { type: "spring", visualDuration: 0.4, bounce: 0.04 } as const;
export const surfaceClose = { type: "spring", visualDuration: 0.34, bounce: 0 } as const;

export const panelContentIn = { duration: 0.24, delay: 0.07, ease: "easeOut" } as const;
export const panelContentOut = { duration: 0.1, ease: "easeIn" } as const;
export const compactContentIn = { duration: 0.16, delay: 0.17, ease: "easeOut" } as const;
export const compactContentOut = { duration: 0.08, ease: "easeOut" } as const;
export const surfaceColorToPanel = { duration: 0.14, ease: "easeOut" } as const;
export const surfaceColorToNotch = { duration: 0.2, delay: 0.08, ease: "easeIn" } as const;

export const instant = { duration: 0 } as const;

export const surfaceShadow = {
  panel: "0px 0px 0px 1px rgba(229,229,229,1), 0px 10px 32px 0px rgba(0,0,0,0.18)",
  notch: "0px 0px 0px 0px rgba(229,229,229,0), 0px 0px 0px 0px rgba(0,0,0,0)",
};
