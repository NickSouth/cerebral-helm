import { createContext, useContext, useMemo, useState, type ReactNode } from "react";
import { DEFAULT_SETTINGS_CATEGORY, type SettingsCategoryId } from "../shell/settings/categories";
import { postShellControl } from "../shell/shellControl";

/**
 * Client-side UI state for the settings window (NIC-63): whether it is open and which category is
 * selected. This is view state only — it is NOT dashboard/bridge state (opening settings changes
 * nothing on the platform), so it lives here like the Heimlich conversation session, not in the
 * store.
 *
 * Two surfaces (backdrop-policy decision, 2026-07-06):
 * - `overlay` (default): the in-page settings window over the dashboard. Inside the native shell,
 *   `openSettings` routes to the dedicated native settings window instead — the dashboard is a
 *   strict backdrop and an in-backdrop overlay could be covered by other apps. Browsers keep the
 *   web overlay (there is no native window to open).
 * - `standalone`: the settings surface IS the whole page (`index.html?surface=settings`, hosted by
 *   the native settings window). Always open; closing asks the native shell to close the window.
 */
interface SettingsController {
  readonly open: boolean;
  readonly activeCategory: SettingsCategoryId;
  readonly openSettings: (category?: SettingsCategoryId) => void;
  readonly closeSettings: () => void;
  readonly setCategory: (category: SettingsCategoryId) => void;
}

const SettingsContext = createContext<SettingsController | null>(null);

export function SettingsProvider({
  children,
  surface = "overlay"
}: {
  children: ReactNode;
  surface?: "overlay" | "standalone";
}) {
  const [open, setOpen] = useState(false);
  const [activeCategory, setActiveCategory] =
    useState<SettingsCategoryId>(DEFAULT_SETTINGS_CATEGORY);

  const value = useMemo<SettingsController>(() => {
    if (surface === "standalone") {
      return {
        open: true,
        activeCategory,
        openSettings: (category) => {
          if (category) {
            setActiveCategory(category);
          }
        },
        closeSettings: () => {
          postShellControl("closeSettings");
        },
        setCategory: setActiveCategory
      };
    }
    return {
      open,
      activeCategory,
      openSettings: (category) => {
        if (category) {
          setActiveCategory(category);
        }
        // Inside the native shell the dedicated settings window is the surface;
        // the web overlay stays for browser previews without a shell channel.
        if (postShellControl("openSettings")) {
          return;
        }
        setOpen(true);
      },
      closeSettings: () => setOpen(false),
      setCategory: setActiveCategory
    };
  }, [surface, open, activeCategory]);

  return <SettingsContext.Provider value={value}>{children}</SettingsContext.Provider>;
}

export function useSettings(): SettingsController {
  const controller = useContext(SettingsContext);
  if (controller === null) {
    throw new Error("useSettings must be used within a SettingsProvider.");
  }
  return controller;
}
