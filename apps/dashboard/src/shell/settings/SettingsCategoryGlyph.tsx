import type { ReactElement } from "react";
import type { SettingsCategoryId } from "./categories";

/**
 * The filled rounded-square mark for a settings category — the way macOS and iOS both signal
 * "this is a place, not a control".
 *
 * Colour is **per category and fixed**: it is identity, so it must not swim when the mode accent
 * changes. Every value is a mode-independent token (status + agent identity) for exactly that
 * reason; drawing these from `--ch-accent-primary` would recolour the whole sidebar on a mode
 * switch and stop them being recognisable at a glance.
 */
const GLYPHS: Readonly<Record<SettingsCategoryId, { tint: string; path: ReactElement }>> = {
  general: {
    tint: "var(--ch-agent-research)",
    path: (
      <>
        <circle cx="12" cy="12" r="3.4" />
        <path d="M12 3v2.4M12 18.6V21M21 12h-2.4M5.4 12H3M18.4 5.6l-1.7 1.7M7.3 16.7l-1.7 1.7M18.4 18.4l-1.7-1.7M7.3 7.3L5.6 5.6" />
      </>
    )
  },
  permissions: {
    tint: "var(--ch-status-error)",
    path: <path d="M12 3l7.5 3.2v5.9c0 4.3-3.2 7.6-7.5 9.4-4.3-1.8-7.5-5.1-7.5-9.4V6.2z" />
  },
  modes: {
    tint: "var(--ch-status-warning)",
    path: (
      <>
        <rect x="3.4" y="3.4" width="7.2" height="7.2" rx="1.4" />
        <rect x="13.4" y="3.4" width="7.2" height="7.2" rx="1.4" />
        <rect x="3.4" y="13.4" width="7.2" height="7.2" rx="1.4" />
        <rect x="13.4" y="13.4" width="7.2" height="7.2" rx="1.4" />
      </>
    )
  },
  actions: {
    tint: "var(--ch-status-success)",
    path: <path d="M13.2 2.4L4.4 14h6.3l-.9 7.6L19.6 10h-6.4z" />
  },
  customization: {
    tint: "var(--ch-agent-project)",
    path: (
      <>
        <circle cx="12" cy="12" r="8.6" />
        <circle cx="9.2" cy="9.6" r="1.5" />
        <circle cx="15" cy="9.6" r="1.5" />
        <circle cx="15.4" cy="14.6" r="1.5" />
      </>
    )
  },
  setup: {
    tint: "var(--ch-mode-executive-secondary)",
    path: <path d="M3.6 7.4h16.8M3.6 12h16.8M3.6 16.6h10.2" />
  }
};

export function SettingsCategoryGlyph({ id }: { id: SettingsCategoryId }) {
  const glyph = GLYPHS[id];
  return (
    <span className="settings-category__mark" style={{ "--cat": glyph.tint } as React.CSSProperties}>
      <svg
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2.1"
        strokeLinecap="round"
        strokeLinejoin="round"
        aria-hidden="true"
        focusable="false"
      >
        {glyph.path}
      </svg>
    </span>
  );
}

export default SettingsCategoryGlyph;
