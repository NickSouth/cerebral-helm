/**
 * The settings categories (NIC-63 / design spec §10 SettingsWindow). One ordered registry drives
 * the sidebar and the content router — no per-category conditionals in the window. Each panel is
 * one of three honest states throughout: editable (validated via `updateSettings`), read-only
 * contract inspection, or unavailable-future (FR-UI-06, FR-CFG-04).
 */
export type SettingsCategoryId =
  "general" | "permissions" | "modes" | "actions" | "customization" | "setup" | "knowledge";

export interface SettingsCategory {
  readonly id: SettingsCategoryId;
  readonly label: string;
  /** One-line orientation shown at the top of the panel. */
  readonly description: string;
}

export const SETTINGS_CATEGORIES: readonly SettingsCategory[] = [
  { id: "general", label: "General", description: "Default mode and application information." },
  {
    id: "permissions",
    label: "Permissions",
    description: "Enabled tools and their deterministic risk & confirmation policy."
  },
  { id: "modes", label: "Modes", description: "The four modes and their configured surfaces." },
  { id: "actions", label: "Actions", description: "Quick actions and the workflows behind them." },
  {
    id: "customization",
    label: "Customization",
    description: "Appearance and motion preferences."
  },
  { id: "setup", label: "Setup", description: "Integrations, onboarding, and data location." },
  { id: "knowledge", label: "Knowledge", description: "Where durable knowledge lives." }
];

export const DEFAULT_SETTINGS_CATEGORY: SettingsCategoryId = SETTINGS_CATEGORIES[0].id;
