function siteUrl() {
  if (process.env.NEXT_PUBLIC_SITE_URL) return process.env.NEXT_PUBLIC_SITE_URL;
  if (process.env.VERCEL_PROJECT_PRODUCTION_URL) return `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}`;
  return "http://localhost:3000";
}

export const site = {
  name: "Refyn",
  url: siteUrl(),
  title: "Refyn: Optimized prompts. Completely free.",
  description:
    "Refyn is the free AI prompt optimizer that lives in your Mac's notch. Turn rough ideas into precise, actionable prompts for Claude Code, Codex, and other coding agents, on your own Mac.",
  repoUrl: "https://github.com/Youseph-Elkhouly/Refyn",
  downloadUrl: process.env.NEXT_PUBLIC_DOWNLOAD_URL ?? "https://github.com/Youseph-Elkhouly/Refyn/releases/latest",
  compatibility: "Free to use · macOS 14 or later · Apple Silicon",
} as const;

export const navLinks = [
  { href: "#demo", label: "Demo" },
  { href: "#examples", label: "Examples" },
  { href: "#features", label: "Features" },
  { href: "#how-it-works", label: "How it works" },
] as const;
