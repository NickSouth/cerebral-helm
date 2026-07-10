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

/** The assistant's default display name, mirroring `EffectiveSettings.defaultAssistantName`
 *  (Swift). Shown until the persisted value is read, and if the read fails. */
export const DEFAULT_ASSISTANT_NAME = "Heimlich";

/**
 * App-wide appearance preferences that outlive the settings window (NIC-63): the reduced-motion
 * override and the assistant's display name (NIC-137).
 *
 * - Reduced motion: a user toggle that forces reduced motion regardless of the OS setting. The OS
 *   `prefers-reduced-motion` media query still governs on its own; this override composes with it
 *   (either being true stills motion). Applied once at the root via `data-reduced-motion` (see
 *   ThemeProvider) so no component re-derives it.
 * - Assistant name: the global display name shown wherever the assistant is identified (bottom bar,
 *   center stage). One name across every mode — distinct from a mode's per-mode `greeting.persona`.
 *
 * Both are seeded from persisted settings via `getSettings` on mount (NIC-141), so the whole
 * dashboard — not just the settings window — honors the stored values at startup. The one-shot seed
 * never clobbers a user edit: once the user has set a value, a late-arriving read is ignored for
 * that value. A failed read keeps the safe defaults (motion on, name `Heimlich`).
 */
interface AppearanceController {
  readonly reducedMotion: boolean;
  readonly setReducedMotion: (value: boolean) => void;
  readonly assistantName: string;
  readonly setAssistantName: (value: string) => void;
}

const AppearanceContext = createContext<AppearanceController | null>(null);

export function AppearanceProvider({ children }: { children: ReactNode }) {
  const bridge = useBridge();
  const [reducedMotion, setReducedMotion] = useState(false);
  const [assistantName, setAssistantName] = useState(DEFAULT_ASSISTANT_NAME);
  // A user edit takes precedence over the async seed forever after — the read
  // resolves within a few ms of mount, but these close the race cleanly. One flag
  // per value so touching one never suppresses the other's seed.
  const motionTouched = useRef(false);
  const nameTouched = useRef(false);

  useEffect(() => {
    let active = true;
    bridge
      .getSettings()
      .then((settings) => {
        if (!active) {
          return;
        }
        if (!motionTouched.current) {
          setReducedMotion(settings.appearance.reducedMotion);
        }
        if (!nameTouched.current) {
          setAssistantName(settings.appearance.assistantName);
        }
      })
      .catch(() => {
        /* A missing read must not gate the UI; keep the safe defaults. */
      });
    return () => {
      active = false;
    };
  }, [bridge]);

  const setReducedMotionFromUser = useCallback((value: boolean) => {
    motionTouched.current = true;
    setReducedMotion(value);
  }, []);

  const setAssistantNameFromUser = useCallback((value: string) => {
    nameTouched.current = true;
    setAssistantName(value);
  }, []);

  const value = useMemo<AppearanceController>(
    () => ({
      reducedMotion,
      setReducedMotion: setReducedMotionFromUser,
      assistantName,
      setAssistantName: setAssistantNameFromUser
    }),
    [reducedMotion, setReducedMotionFromUser, assistantName, setAssistantNameFromUser]
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
