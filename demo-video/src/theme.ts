import { loadFont } from "@remotion/fonts";
import { Easing, staticFile } from "remotion";

const displayFamily = "Instrument Serif";

loadFont({ family: displayFamily, url: staticFile("instrument-serif-italic.woff2"), style: "italic", weight: "400" });

export const fonts = {
  display: `"${displayFamily}", Georgia, serif`,
  sans: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif',
  mono: '"SF Mono", ui-monospace, Menlo, Consolas, monospace',
};

export const colors = {
  white: "#ffffff",
  black: "#000000",
  muted: "#8c8c8c",
  appText: "#111111",
  appMuted: "#737373",
  appSecondary: "#666666",
  appLine: "#e5e5e5",
  appSurface: "#f7f7f7",
  desktop: "#161616",
  wallpaperRing: "#1f1f1f",
  terminal: "#0a0a0a",
};

export const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

export const ease = Easing.bezier(0.22, 0.9, 0.26, 1);
export const easeInOut = Easing.bezier(0.65, 0, 0.35, 1);
