export type PromptSection = {
  title: string;
  items: string[];
  ordered?: boolean;
};

export type PromptDoc = PromptSection[];

export type DemoMode = "Auto" | "Basic" | "Advanced";

export const demoRequest = "my app is slow and buggy, fix it";

const investigation = [
  "Reproduce the slowness and each bug, and write down the exact steps.",
  "Profile the slowest flows before changing code, and record a baseline.",
  "Check logs and failing tests for errors that explain the bugs.",
  "Rank findings by user impact and name the root cause of each.",
];

const constraints = [
  "Only change code tied to a confirmed cause.",
  "Keep public APIs and existing behavior unless a bug requires otherwise.",
  "Ask before adding a dependency or running a migration.",
];

const verification = [
  "Re-run the baseline and report before and after numbers.",
  "Add a regression test for every bug you fix.",
  "Run the full test suite and report the result.",
];

const objective = ["Find what is making the app slow and buggy, then fix the causes you can confirm."];

export const demoOutputs: Record<DemoMode, PromptDoc> = {
  Basic: [
    {
      title: "Objective",
      items: [
        "Investigate why the app is slow and buggy, reproduce the problems, and fix the root causes you can confirm. Limit changes to those causes, and report how you verified each fix.",
      ],
    },
  ],
  Auto: [
    { title: "Objective", items: objective },
    { title: "Investigation", items: investigation, ordered: true },
    { title: "Constraints", items: constraints },
    { title: "Verification", items: verification },
  ],
  Advanced: [
    { title: "Objective", items: objective },
    { title: "Constraints", items: constraints },
    { title: "Stage 1 — Investigate", items: investigation, ordered: true },
    {
      title: "Stage 2 — Fix",
      items: ["Fix one confirmed cause at a time, highest impact first.", "Keep each fix in its own reviewable change."],
      ordered: true,
    },
    { title: "Stage 3 — Verify", items: verification },
    { title: "Working method", items: ["If the same fix fails three times, stop and report what you tried."] },
  ],
};

export const demoPlan = [
  { label: "Intent", items: objective },
  { label: "Tasks", items: investigation.map((task, index) => `T${index + 1}: ${task}`) },
  { label: "Constraints", items: constraints },
  { label: "Verification", items: verification },
];

export function promptToText(doc: PromptDoc) {
  return doc
    .map(({ title, items, ordered }) => {
      const body = items.map((item, index) => (items.length === 1 && !ordered ? item : `${ordered ? `${index + 1}.` : "-"} ${item}`));
      return [`## ${title}`, ...body].join("\n");
    })
    .join("\n\n");
}

export type Example = {
  id: string;
  label: string;
  before: string;
  added: string[];
  after: PromptDoc;
};

export const examples: Example[] = [
  {
    id: "bug-fixing",
    label: "Bug Fixing",
    before: "checkout keeps failing sometimes when ppl use a coupon?? not sure why. can u fix it",
    added: ["A way to reproduce it", "A hard stop on guessing", "A regression test"],
    after: [
      { title: "Objective", items: ["Find and fix the intermittent checkout failure that occurs when a coupon is applied."] },
      {
        title: "Investigation",
        ordered: true,
        items: [
          "Reproduce with a valid, an expired, and an already-used coupon. Record which combinations fail.",
          "Trace the coupon from input to order total. Look for race conditions, stale cart state, and unhandled API errors.",
          "State the root cause before editing any code.",
        ],
      },
      { title: "Constraints", items: ["Keep the fix inside the coupon and checkout flow.", "Don't change pricing rules or which coupons are valid."] },
      { title: "Verification", items: ["Add a regression test that fails before the fix and passes after it.", "Confirm checkout still completes without a coupon."] },
    ],
  },
  {
    id: "ui-design",
    label: "UI Design",
    before: "make the settings page look nicer, its kinda ugly and cramped",
    added: ["What “nicer” means", "Limits on the redesign", "Checks at every width"],
    after: [
      { title: "Objective", items: ["Improve the visual hierarchy and spacing of the settings page without changing what it does."] },
      {
        title: "Tasks",
        ordered: true,
        items: [
          "Group related settings under clear section headings.",
          "Apply the existing spacing and type tokens so sections have room and a consistent rhythm.",
          "Align labels, help text, and controls so the page scans in one pass.",
        ],
      },
      { title: "Constraints", items: ["Reuse existing components and design tokens.", "Add no new dependencies.", "Every setting keeps its current behavior."] },
      { title: "Verification", items: ["Check the page at mobile, tablet, and desktop widths.", "Tab through every control and confirm the focus order and focus ring."] },
    ],
  },
  {
    id: "feature-development",
    label: "Feature Development",
    before: "add dark mode",
    added: ["The actual scope", "An order of work", "Edge cases to test"],
    after: [
      { title: "Objective", items: ["Add a dark theme people can choose, following the system setting by default."] },
      {
        title: "Tasks",
        ordered: true,
        items: [
          "Find how colors are defined today and move hard-coded values into semantic tokens.",
          "Define dark values for every token.",
          "Add a System, Light, and Dark setting and persist the choice.",
          "Apply the theme before first paint so the page never flashes.",
        ],
      },
      { title: "Constraints", items: ["Change color only. Leave layout and copy alone."] },
      {
        title: "Verification",
        items: ["Confirm text meets WCAG AA contrast in both themes.", "Reload and confirm the choice persists.", "Change the system appearance and confirm System mode follows it."],
      },
    ],
  },
  {
    id: "refactoring",
    label: "Refactoring",
    before: "this auth file is like 900 lines and a mess, clean it up but dont break stuff",
    added: ["A definition of “don't break”", "Safety tests first", "Small, reversible steps"],
    after: [
      { title: "Objective", items: ["Split the authentication file into focused modules with no change in behavior."] },
      {
        title: "Steps",
        ordered: true,
        items: [
          "Map its responsibilities, public exports, and callers.",
          "Add tests around current behavior wherever coverage is missing.",
          "Extract one responsibility at a time and run the tests after each move.",
          "Keep the original path re-exporting the public API.",
        ],
      },
      { title: "Constraints", items: ["The public API and session format stay the same.", "No new features or dependency upgrades."] },
      { title: "Verification", items: ["Run the full test suite.", "Exercise login, logout, and token refresh by hand."] },
    ],
  },
  {
    id: "performance-optimization",
    label: "Performance Optimization",
    before: "dashboard takes forever to load, make it fast",
    added: ["Measure before changing", "Fix what's actually slow", "Proof it got faster"],
    after: [
      { title: "Objective", items: ["Reduce the dashboard's load time by fixing its largest measured bottlenecks."] },
      {
        title: "Investigation",
        ordered: true,
        items: [
          "Record a baseline on a production-sized account: time to first data, largest contentful paint, and the request waterfall.",
          "Rank the causes: slow queries, over-fetching, bundle size, and unnecessary re-renders.",
          "Fix the top two, one at a time, and measure after each.",
        ],
      },
      { title: "Constraints", items: ["Displayed data and permissions stay the same.", "Don't add a cache without defining when it invalidates."] },
      { title: "Verification", items: ["Report before and after numbers for the same account.", "Confirm the dashboard still shows fresh data."] },
    ],
  },
];
