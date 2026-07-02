import type { ReactNode } from "react";

/**
 * Mode identity glyphs for the R1 switcher (design spec §5.9): a fixed icon per mode id, sitting
 * above the mode label in the 2×2 toggle. These are solid silhouettes (fill, not stroke) so the
 * active toggle reads as "solid-filled with the mode color" — the icon inherits its fill from the
 * option's `currentColor`, which resolves to the mode accent when active and a muted tone
 * otherwise. Identity (shape) is fixed per id; only the *color* is mode-driven, and it flows in
 * through the token cascade — never a per-mode conditional here (constitution §5). NIC-118 may
 * replace these with the final identity assets.
 */
const GLYPHS: Readonly<Record<string, ReactNode>> = {
  // Crown — Executive.
  executive: (
    <path d="M3 8l3.5 4L12 6l5.5 6L21 8v8.5a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 16.5z" />
  ),
  // Angle brackets with a larger slash between, spaced so they don't touch — Developer (`</>`).
  developer: (
    <>
      <path d="M7.6 6.6l1.5 1.5L6 12l3.1 3.9-1.5 1.5L3 12z" />
      <path d="M16.4 6.6l-1.5 1.5L18 12l-3.1 3.9 1.5 1.5L21 12z" />
      <path d="M13.9 5.6l1.7.6-5 12.2-1.7-.6z" />
    </>
  ),
  // Mortarboard — School.
  school: <path d="M12 4 1 9l11 5 11-5zM5 12.6v3.1c0 1.5 3.1 2.7 7 2.7s7-1.2 7-2.7v-3.1l-7 3.2z" />,
  // Game controller — Entertainment.
  entertainment: (
    <path d="M7.5 8.5h9a4.4 4.4 0 0 1 4.2 5.7l-.4 1.4a2.5 2.5 0 0 1-4.3 1L14.6 15H9.4l-1.4 1.6a2.5 2.5 0 0 1-4.3-1l-.4-1.4A4.4 4.4 0 0 1 7.5 8.5zM7 10.5v1.5H5.5v1.4H7V15h1.4v-1.6H10v-1.4H8.4v-1.5zm8.4.3a1 1 0 1 0 0 2 1 1 0 0 0 0-2zm2 2.2a1 1 0 1 0 0 2 1 1 0 0 0 0-2z" />
  )
};

export function ModeGlyph({ mode }: { mode: string }) {
  return (
    <svg
      className="mode-glyph"
      viewBox="0 0 24 24"
      width="20"
      height="20"
      fill="currentColor"
      fillRule="evenodd"
      aria-hidden="true"
      focusable="false"
    >
      {GLYPHS[mode] ?? GLYPHS.executive}
    </svg>
  );
}
