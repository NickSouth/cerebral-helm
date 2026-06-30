import type { ReactNode } from "react";
import type { AppCategory } from "../appCatalog/appCatalog";

/**
 * Pre-Mac placeholder app icons: generic monochrome category glyphs (owner decision), not
 * brand logos. They inherit color from the surrounding text token via `currentColor`, so
 * they re-theme by mode for free. NIC-118 may refine; the Mac host supplies real OS icons.
 */
const GLYPHS: Readonly<Record<AppCategory, ReactNode>> = {
  browser: (
    <>
      <circle cx="12" cy="12" r="9" />
      <path d="M3 12h18M12 3c2.6 2.6 2.6 15.4 0 18M12 3c-2.6 2.6-2.6 15.4 0 18" />
    </>
  ),
  mail: (
    <>
      <rect x="3" y="5" width="18" height="14" rx="2" />
      <path d="M3.5 7l8.5 6 8.5-6" />
    </>
  ),
  files: <path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />,
  assistant: (
    <>
      <path d="M4 5h16a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1h-8l-4 3v-3H4a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1z" />
      <path d="M12 8v5M9.5 10.5h5" />
    </>
  ),
  code: <path d="M9 8l-4 4 4 4M15 8l4 4-4 4" />,
  terminal: (
    <>
      <rect x="3" y="4" width="18" height="16" rx="2" />
      <path d="M7 9l3 3-3 3M12.5 15H17" />
    </>
  ),
  tasks: (
    <>
      <path d="M10 6h10M10 12h10M10 18h10" />
      <path d="M4 6l1.4 1.4L8 4.8M4 12l1.4 1.4L8 10.8M4 18l1.4 1.4L8 16.8" />
    </>
  ),
  learning: (
    <>
      <path d="M3 8l9-4 9 4-9 4-9-4z" />
      <path d="M7 10.5V15c0 1 2.4 2 5 2s5-1 5-2v-4.5" />
    </>
  ),
  music: (
    <>
      <circle cx="7" cy="17" r="2.6" />
      <circle cx="17" cy="15" r="2.6" />
      <path d="M9.6 17V6.5l9.8-2v11" />
    </>
  ),
  video: (
    <>
      <rect x="3" y="5" width="18" height="14" rx="2" />
      <path d="M10 9l5 3-5 3z" />
    </>
  ),
  games: (
    <>
      <rect x="2.5" y="7.5" width="19" height="9" rx="4.5" />
      <path d="M7 12h3M8.5 10.5v3" />
      <circle cx="16" cy="11.5" r="1" />
      <circle cx="18" cy="13.5" r="1" />
    </>
  ),
  chat: <path d="M4 5h16a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1h-8l-4 3v-3H4a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1z" />,
  photos: (
    <>
      <rect x="3" y="5" width="18" height="14" rx="2" />
      <circle cx="8.5" cy="10" r="1.5" />
      <path d="M21 17l-5-5-4 4-2-2-6.5 6.5" />
    </>
  )
};

export function AppGlyph({ category }: { category: AppCategory }) {
  return (
    <svg
      className="app-glyph"
      viewBox="0 0 24 24"
      width="20"
      height="20"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      {GLYPHS[category]}
    </svg>
  );
}
