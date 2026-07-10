import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode
} from "react";
import { useBridge } from "./BridgeProvider";

/**
 * App-wide appearance preferences that outlive the settings window (NIC-63). Currently just the
 * reduced-motion override: a user toggle that forces reduced motion regardless of the OS setting.
 * The OS `prefers-reduced-motion` media query still governs on its own; this override composes
 * with it (either being true stills motion). Applied once at the root via `data-reduced-motion`
 * (see ThemeProvider) so no component re-derives it.
 *
 * The initial value is seeded from persisted settings via `getSettings` on mount (NIC-141), so the
 * whole dashboard — not just the settings toggle — honors the stored preference at startup. The
 * one-shot seed never clobbers a user toggle: once the user has set the value, a late-arriving read
 * is ignored. A failed read keeps the safe default (motion on).
 */
interface AppearanceController {
  readonly reducedMotion: boolean;
  readonly setReducedMotion: (value: boolean) => void;
}

const AppearanceContext = createContext<AppearanceController | null>(null);

export function AppearanceProvider({ children }: { children: ReactNode }) {
  const bridge = useBridge();
  const [reducedMotion, setReducedMotion] = useState(false);
  // A user toggle takes precedence over the async seed forever after — the read
  // resolves within a few ms of mount, but this closes the race cleanly.
  const userTouched = useRef(false);

  useEffect(() => {
    let active = true;
    bridge
      .getSettings()
      .then((settings) => {
        if (active && !userTouched.current) {
          setReducedMotion(settings.appearance.reducedMotion);
        }
      })
      .catch(() => {
        /* A missing read must not gate the UI; keep the safe default (motion on). */
      });
    return () => {
      active = false;
    };
  }, [bridge]);

  const setReducedMotionFromUser = useCallback((value: boolean) => {
    userTouched.current = true;
    setReducedMotion(value);
  }, []);

  const value = useMemo<AppearanceController>(
    () => ({ reducedMotion, setReducedMotion: setReducedMotionFromUser }),
    [reducedMotion, setReducedMotionFromUser]
  );
  return <AppearanceContext.Provider value={value}>{children}</AppearanceContext.Provider>;
}

export function useAppearance(): AppearanceController {
  const controller = useContext(AppearanceContext);
  if (controller === null) {
    throw new Error("useAppearance must be used within an AppearanceProvider.");
  }
  return controller;
}
