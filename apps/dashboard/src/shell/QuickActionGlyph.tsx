import type { ReactNode } from "react";

/**
 * Quick-action slot glyphs — the leading icon every slot carries (docs/quick-actions/PLAN.md,
 * § Visual rules). Muted by default so the *label* still leads; the slot takes the mode accent only
 * while its own surface (Report or Input) is open, which buys a consistent open-state indicator
 * across all 32 slots for free.
 *
 * Hand-authored 24×24 line paths in the same house construction as {@link AppGlyph} and
 * {@link PanelGlyph}: inline SVG inheriting `currentColor`, so they re-theme by mode for nothing and
 * no external CDN or icon package is involved. The registry's icon **names** follow Tabler's, so a
 * real Tabler path can be dropped into an entry later without touching a call site.
 *
 * The names live in the dispatch registry beside `label` and `archetype`, because that is the one
 * place that knows what an action *is*. `quickActionGlyphs.test.ts` asserts every registered icon
 * resolves here, so a registry entry can never name a glyph that does not exist.
 */
export type QuickActionGlyphName =
  | "activity"
  | "ball-football"
  | "brand-youtube"
  | "calendar"
  | "calendar-plus"
  | "disco"
  | "external-link"
  | "file-text"
  | "folder-plus"
  | "git-branch"
  | "layout-grid"
  | "mail"
  | "message"
  | "movie"
  | "notes"
  | "playlist"
  | "power"
  | "search"
  | "terminal-2"
  | "ticket";

const GLYPHS: Readonly<Record<QuickActionGlyphName, ReactNode>> = {
  activity: <path d="M3 12h4l3 7 4-14 3 7h4" />,
  "ball-football": (
    <>
      <circle cx="12" cy="12" r="9" />
      <path d="M12 7.2l4.4 3.2-1.7 5.2H9.3L7.6 10.4z" />
      <path d="M12 3v4.2M4.3 8.8l3.3 1.6M19.7 8.8l-3.3 1.6M8.2 20.4l1.1-4.8M15.8 20.4l-1.1-4.8" />
    </>
  ),
  "brand-youtube": (
    <>
      <rect x="3" y="5.5" width="18" height="13" rx="4" />
      <path d="M10 9.5l5 2.5-5 2.5z" />
    </>
  ),
  calendar: (
    <>
      <rect x="4" y="5" width="16" height="16" rx="2" />
      <path d="M8 3v4M16 3v4M4 10h16" />
    </>
  ),
  "calendar-plus": (
    <>
      <path d="M20 12.5V7a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h6" />
      <path d="M8 3v4M16 3v4M4 10h16" />
      <path d="M15.5 18.5h5M18 16v5" />
    </>
  ),
  disco: (
    <>
      <circle cx="12" cy="14.5" r="6.2" />
      <path d="M12 8.3V3.5M9.5 3.5h5" />
      <path d="M5.8 14.5h12.4M12 8.3v12.4" />
      <path d="M8.4 10.1c1.5 2.8 1.5 6 0 8.8M15.6 10.1c-1.5 2.8-1.5 6 0 8.8" />
    </>
  ),
  "external-link": (
    <>
      <path d="M12 6H6.5A2.5 2.5 0 0 0 4 8.5v9A2.5 2.5 0 0 0 6.5 20h9a2.5 2.5 0 0 0 2.5-2.5V12" />
      <path d="M11 13l9-9M15 4h5v5" />
    </>
  ),
  "file-text": (
    <>
      <path d="M14 3v4a1 1 0 0 0 1 1h4" />
      <path d="M18 9v10a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h6z" />
      <path d="M9.5 12.5h5M9.5 16h5" />
    </>
  ),
  "folder-plus": (
    <>
      <path d="M12 19H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h3.5l2 2.5H19a2 2 0 0 1 2 2v3" />
      <path d="M15.5 18.5h5M18 16v5" />
    </>
  ),
  "git-branch": (
    <>
      <circle cx="7" cy="6" r="2" />
      <circle cx="7" cy="18" r="2" />
      <circle cx="17" cy="7.5" r="2" />
      <path d="M7 8v8M17 9.5v.5c0 2.5-2 4.5-4.5 4.5h-1A4.5 4.5 0 0 0 7 17" />
    </>
  ),
  "layout-grid": (
    <>
      <rect x="4" y="4" width="7" height="7" rx="1.5" />
      <rect x="13" y="4" width="7" height="7" rx="1.5" />
      <rect x="4" y="13" width="7" height="7" rx="1.5" />
      <rect x="13" y="13" width="7" height="7" rx="1.5" />
    </>
  ),
  mail: (
    <>
      <rect x="3" y="5" width="18" height="14" rx="2" />
      <path d="M3.5 7l8.5 6 8.5-6" />
    </>
  ),
  message: (
    <>
      <path d="M18 4H6a3 3 0 0 0-3 3v7a3 3 0 0 0 3 3h2v4l5-4h5a3 3 0 0 0 3-3V7a3 3 0 0 0-3-3z" />
      <path d="M8 8.5h8M8 12h5" />
    </>
  ),
  movie: (
    <>
      <rect x="3" y="5" width="18" height="14" rx="2" />
      <path d="M7.5 5v14M16.5 5v14" />
      <path d="M3 9.5h4.5M3 14.5h4.5M16.5 9.5H21M16.5 14.5H21" />
    </>
  ),
  notes: (
    <>
      <rect x="5" y="3" width="14" height="18" rx="2" />
      <path d="M9 7.5h6M9 11h6M9 14.5h3.5" />
    </>
  ),
  playlist: (
    <>
      <circle cx="17" cy="17" r="3" />
      <path d="M20 17V6M4 7h11M4 11h11M4 15h7" />
    </>
  ),
  power: (
    <>
      <path d="M7 6.5a7 7 0 1 0 10 0" />
      <path d="M12 3.5V11" />
    </>
  ),
  search: (
    <>
      <circle cx="10.5" cy="10.5" r="6.5" />
      <path d="M20 20l-4.8-4.8" />
    </>
  ),
  "terminal-2": (
    <>
      <rect x="3" y="4" width="18" height="16" rx="2" />
      <path d="M7.5 9.5l3 2.5-3 2.5M13 15h3.5" />
    </>
  ),
  ticket: (
    <>
      <path d="M5 5.5h14a1.5 1.5 0 0 1 1.5 1.5v2.6a2.4 2.4 0 0 0 0 4.8V17a1.5 1.5 0 0 1-1.5 1.5H5A1.5 1.5 0 0 1 3.5 17v-2.6a2.4 2.4 0 0 0 0-4.8V7A1.5 1.5 0 0 1 5 5.5z" />
      <path d="M14.5 8v1.5M14.5 11.2v1.6M14.5 14.5V16" />
    </>
  )
};

/** Whether a name resolves to a drawable glyph — the guard the registry test asserts against. */
export function isQuickActionGlyphName(name: string): name is QuickActionGlyphName {
  return name in GLYPHS;
}

/**
 * The slot's leading glyph, or `null` for a name with no drawing. An unknown name leaves the label
 * standing alone rather than drawing a broken box: the test above makes that unreachable in a valid
 * build, so this only covers a runtime-supplied id (a stale persisted config).
 */
export function QuickActionGlyph({ name, size = 16 }: { name: string; size?: number }) {
  if (!isQuickActionGlyphName(name)) {
    return null;
  }
  return (
    <svg
      className="quick-action__glyph"
      viewBox="0 0 24 24"
      width={size}
      height={size}
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
