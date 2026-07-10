/**
 * The settings categories (NIC-63 / design spec §10 SettingsWindow). One ordered registry drives
 * the sidebar and the content router — no per-category conditionals in the window. Each panel is
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
  /** One-line orientation shown at the top of the panel. */
  readonly description: string;
}

export const SETTINGS_CATEGORIES: readonly SettingsCategory[] = [
  {
    id: "general",
    label: "General",
    description: "Launch, display, motion, and the command-palette shortcut."
  },
  {
    id: "permissions",
    label: "Permissions",
    description: "Enabled tools and their deterministic risk & confirmation policy."
  },
  {
    id: "modes",
    label: "Modes",
    description: "The modes, the default, and window behavior."
  },
  { id: "actions", label: "Actions", description: "Quick actions and the workflows behind them." },
  {
    id: "customization",
    label: "Customization",
    description: "Mode colors and the assistant name."
  },
  {
    id: "setup",
    label: "Setup",
    description: "Knowledge location, integrations, and onboarding."
  }
];

export const DEFAULT_SETTINGS_CATEGORY: SettingsCategoryId = SETTINGS_CATEGORIES[0].id;
