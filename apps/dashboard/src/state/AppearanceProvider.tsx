import { createContext, useContext, useMemo, useState, type ReactNode } from "react";

/**
 * App-wide appearance preferences that outlive the settings window (NIC-63). Currently just the
 * reduced-motion override: a user toggle that forces reduced motion regardless of the OS setting.
 * The OS `prefers-reduced-motion` media query still governs on its own; this override composes
 * with it (either being true stills motion). Applied once at the root via `data-reduced-motion`
 * (see ThemeProvider) so no component re-derives it.
 */
interface AppearanceController {
  readonly reducedMotion: boolean;
  readonly setReducedMotion: (value: boolean) => void;
}

const AppearanceContext = createContext<AppearanceController | null>(null);

export function AppearanceProvider({ children }: { children: ReactNode }) {
  const [reducedMotion, setReducedMotion] = useState(false);
  const value = useMemo<AppearanceController>(() => ({ reducedMotion, setReducedMotion }), [reducedMotion]);
  return <AppearanceContext.Provider value={value}>{children}</AppearanceContext.Provider>;
}

export function useAppearance(): AppearanceController {
  const controller = useContext(AppearanceContext);
  if (controller === null) {
    throw new Error("useAppearance must be used within an AppearanceProvider.");
  }
  return controller;
}
