/**
 * The settings categories (NIC-63 / design spec §10 SettingsWindow). One ordered registry drives
 * the sidebar and the content router — no per-category conditionals in the window.
 *
 * There is deliberately NO per-category description (owner, 2026-08-07): a category explains
 * itself through its mark, its name, and the rows inside it, and a paragraph restating that was
 * the bulk of what made this window feel heavy. Each panel is
 * one of three honest states throughout: editable (validated via `updateSettings`), read-only
 * contract inspection, or unavailable-future (FR-UI-06, FR-CFG-04).
 */
export type SettingsCategoryId =
  | "general"
  | "permissions"
  | "modes"
  | "actions"
  | "customization"
  | "setup";

export interface SettingsCategory {
  readonly id: SettingsCategoryId;
  readonly label: string;
}

export const SETTINGS_CATEGORIES: readonly SettingsCategory[] = [
  {
    id: "general",
    label: "General"
  },
  {
    id: "permissions",
    label: "Permissions"
  },
  {
    id: "modes",
    label: "Modes"
  },
  { id: "actions", label: "Actions" },
  {
    id: "customization",
    label: "Customization"
  },
  {
    id: "setup",
    label: "Setup"
  }
];

export const DEFAULT_SETTINGS_CATEGORY: SettingsCategoryId = SETTINGS_CATEGORIES[0].id;
