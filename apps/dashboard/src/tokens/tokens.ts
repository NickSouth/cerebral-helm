/*
 * Token registry — the typed view of the design tokens that the resolution gate
 * (NIC-51 Increment 4) derives its manifest from, and that components/tests use to
 * reason about mode token names without re-deriving them.
 *
 * The CSS in tokens.css is the runtime source of truth for VALUES; this module is the
 * source of truth for the NAMES that config files reference and how they map to CSS
 * custom properties. The two are kept in lockstep by tokens.test.ts.
 */

export const MODE_IDS = ["executive", "developer", "school", "entertainment"] as const;
export type ModeId = (typeof MODE_IDS)[number];

/**
 * Mode theme token names exactly as they appear in `config/modes/*.json`
 * (`theme.accentPrimary` / `theme.accentSecondary`).
 */
export const MODE_TOKEN_NAMES = [
  "executive.primary",
  "executive.secondary",
  "developer.primary",
  "developer.secondary",
  "school.primary",
  "school.secondary",
  "entertainment.primary",
  "entertainment.secondary",
] as const;
export type ModeTokenName = (typeof MODE_TOKEN_NAMES)[number];

/** Semantic accent tokens that every component reads (resolved per mode via data-mode). */
export const SEMANTIC_ACCENT_VARS = ["--ch-accent-primary", "--ch-accent-secondary"] as const;

/** Map a dotted config token name (e.g. "executive.primary") to its CSS custom property. */
export function modeTokenCssVar(name: string): string {
  return `--ch-mode-${name.replace(/\./g, "-")}`;
}

/** Whether a dotted token name is a registered mode theme token. */
export function isRegisteredModeTokenName(name: string): name is ModeTokenName {
  return (MODE_TOKEN_NAMES as readonly string[]).includes(name);
}

/**
 * Map a dashboard mode label (e.g. the `DashboardMode` "Developer" carried in state)
 * to its lowercase token mode id used by the `data-mode` attribute. Throws on an
 * unknown mode rather than silently theming nothing.
 */
export function toModeId(mode: string): ModeId {
  const id = mode.toLowerCase();
  if ((MODE_IDS as readonly string[]).includes(id)) {
    return id as ModeId;
  }
  throw new Error(`Unknown dashboard mode: ${mode}`);
}
