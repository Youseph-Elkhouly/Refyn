# Refyn website

The landing page for Refyn. Next.js (App Router), TypeScript, Tailwind CSS, and Motion. It is fully static and has no backend.

## Develop

    npm install
    npm run dev

Checks: `npx tsc --noEmit`, `npm run lint`, `npm run build`.

## Configure

| Variable | Purpose | Default |
| --- | --- | --- |
| `NEXT_PUBLIC_DOWNLOAD_URL` | Where every Download button points | The GitHub repo's latest release |
| `NEXT_PUBLIC_SITE_URL` | Canonical URL, Open Graph, and sitemap | The Vercel production URL, then localhost |

## Deploy

On Vercel, import the repository and set **Root Directory** to `website`.

## Where things live

- `src/content/prompts.ts`: every example prompt, before and after.
- `src/lib/motion.ts`: notch timings, copied from `Theme.Motion` in the macOS app. Keep them in sync.
- `src/components/refyn/`: the simulated app. `useRefynDemo` holds its state; `RefynNotch` is the animated surface; `RefynPanel` is the UI, laid out from the SwiftUI views.
- `src/components/mac/`: the MacBook and its desktop.
- `src/components/site/`: the page sections.

The feature copy in `src/components/site/Features.tsx` should only describe what the current app build does.
