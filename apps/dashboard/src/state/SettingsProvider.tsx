import { createContext, useContext, useMemo, useState, type ReactNode } from "react";
import { DEFAULT_SETTINGS_CATEGORY, type SettingsCategoryId } from "../shell/settings/categories";

/**
 * Client-side UI state for the settings window (NIC-63): whether it is open and which category is
 * selected. This is view state only — it is NOT dashboard/bridge state (opening settings changes
 * nothing on the platform), so it lives here like the Heimlich conversation session, not in the
 * store. The window composites over the dashboard and never replaces it.
 */
interface SettingsController {
  readonly open: boolean;
  readonly activeCategory: SettingsCategoryId;
  readonly openSettings: (category?: SettingsCategoryId) => void;
  readonly closeSettings: () => void;
  readonly setCategory: (category: SettingsCategoryId) => void;
}

const SettingsContext = createContext<SettingsController | null>(null);

export function SettingsProvider({ children }: { children: ReactNode }) {
  const [open, setOpen] = useState(false);
  const [activeCategory, setActiveCategory] = useState<SettingsCategoryId>(DEFAULT_SETTINGS_CATEGORY);

  const value = useMemo<SettingsController>(
    () => ({
      open,
      activeCategory,
      openSettings: (category) => {
        if (category) {
          setActiveCategory(category);
        }
        setOpen(true);
      },
      closeSettings: () => setOpen(false),
      setCategory: setActiveCategory
    }),
    [open, activeCategory]
  );

  return <SettingsContext.Provider value={value}>{children}</SettingsContext.Provider>;
}

export function useSettings(): SettingsController {
  const controller = useContext(SettingsContext);
  if (controller === null) {
    throw new Error("useSettings must be used within a SettingsProvider.");
  }
  return controller;
}
