import type { ReactNode } from "react";

/**
 * Panel eyebrow glyphs: the small top-right category icons every rail panel carries (visual
 * reference — icon-first annotation). Monochrome line icons that inherit color from the
 * eyebrow via `currentColor`, so they re-theme for free. Same construction as {@link AppGlyph}.
 * NIC-118 may refine the identity set; these are placeholders keyed by semantic panel name.
 */
export type PanelGlyphName =
  | "today"
  | "system-health"
  | "news"
  | "mode"
  | "agents"
  | "market"
  | "projects"
  | "git"
  | "deadlines"
  | "music"
  | "courses"
  | "media"
  | "widget";

const GLYPHS: Readonly<Record<PanelGlyphName, ReactNode>> = {
  today: (
    <>
      <rect x="3.5" y="4.5" width="17" height="16" rx="2" />
      <path d="M3.5 9h17M8 3v3M16 3v3" />
    </>
  ),
  "system-health": <path d="M3 12h3.5l2-6 3 12 2.5-8 1.5 4h4.5" />,
  news: (
    <>
      <rect x="3.5" y="4.5" width="17" height="15" rx="2" />
      <path d="M7 8.5h6M7 12h10M7 15.5h10" />
    </>
  ),
  mode: (
    <>
      <rect x="3" y="7.5" width="18" height="9" rx="4.5" />
      <circle cx="15.5" cy="12" r="2.5" />
    </>
  ),
  agents: (
    <>
      <circle cx="9" cy="9" r="3" />
      <path d="M3.5 19c0-3 2.5-5 5.5-5s5.5 2 5.5 5" />
      <path d="M16 7.5a3 3 0 0 1 0 5.4M17.5 19c0-2.2-1-3.9-2.6-4.7" />
    </>
  ),
  market: <path d="M4 16l4.5-5 3 3L20 6M20 6v4M20 6h-4" />,
  projects: <path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />,
  git: (
    <>
      <circle cx="6" cy="6" r="2.2" />
      <circle cx="6" cy="18" r="2.2" />
      <circle cx="18" cy="9" r="2.2" />
      <path d="M6 8.2v7.6M18 11.2c0 3-3.6 3.3-6 3.3" />
    </>
  ),
  deadlines: (
    <>
      <circle cx="12" cy="13" r="7" />
      <path d="M12 9.5V13l2.5 1.5M9 3h6" />
    </>
  ),
  music: (
    <>
      <circle cx="7" cy="17" r="2.6" />
      <circle cx="17" cy="15" r="2.6" />
      <path d="M9.6 17V6.5l9.8-2v11" />
    </>
  ),
  courses: (
    <>
      <path d="M3 8l9-4 9 4-9 4-9-4z" />
      <path d="M7 10.5V15c0 1 2.4 2 5 2s5-1 5-2v-4.5" />
    </>
  ),
  media: (
    <>
      <rect x="3" y="5" width="18" height="14" rx="2" />
      <path d="M10 9l5 3-5 3z" />
    </>
  ),
  widget: (
    <>
      <rect x="4" y="4" width="7" height="7" rx="1.5" />
      <rect x="13" y="4" width="7" height="7" rx="1.5" />
      <rect x="4" y="13" width="7" height="7" rx="1.5" />
      <rect x="13" y="13" width="7" height="7" rx="1.5" />
    </>
  )
};

export function PanelGlyph({ name }: { name: PanelGlyphName }) {
  return (
    <svg
      className="panel-glyph"
      viewBox="0 0 24 24"
      width="16"
      height="16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      {GLYPHS[name]}
    </svg>
  );
}
