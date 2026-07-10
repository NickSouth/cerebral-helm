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
import { modeTokenCssVar } from "../tokens/tokens";
import type { SettingsSnapshot } from "../bridge/cerebralBridge";

/** The assistant's default display name, mirroring `EffectiveSettings.defaultAssistantName`
 *  (Swift). Shown until the persisted value is read, and if the read fails. */
export const DEFAULT_ASSISTANT_NAME = "Heimlich";

/**
 * App-wide appearance preferences that outlive the settings window (NIC-63): the reduced-motion
 * override, the assistant's display name, and per-mode accent-color overrides (NIC-137).
 *
 * - Reduced motion: a user toggle that forces reduced motion regardless of the OS setting. Applied
 *   once at the root via `data-reduced-motion` (see ThemeProvider) so no component re-derives it.
 * - Assistant name: the global display name shown wherever the assistant is identified. One name
 *   across every mode — distinct from a mode's per-mode `greeting.persona`.
 * - Mode colors: sparse per-mode accent overrides keyed by design-token name (e.g.
 *   `executive.primary`). Applied by overriding the corresponding `--ch-mode-*` CSS variable on the
 *   document root, so any mode re-themes live; an un-overridden channel keeps its tokens.css default.
 *
 * All three are seeded from persisted settings via `getSettings` on mount (NIC-141), so the whole
 * dashboard — not just the settings window — honors the stored values at startup. The one-shot seed
 * never clobbers a user edit: once the user has changed a value, a late-arriving read is ignored for
 * that value. A failed read keeps the safe defaults (motion on, name `Heimlich`, no color overrides).
 */
interface AppearanceController {
  readonly reducedMotion: boolean;
  readonly setReducedMotion: (value: boolean) => void;
  readonly assistantName: string;
  readonly setAssistantName: (value: string) => void;
  readonly modeColors: Readonly<Record<string, string>>;
  readonly setModeColor: (tokenName: string, hex: string) => void;
}

const AppearanceContext = createContext<AppearanceController | null>(null);

export function AppearanceProvider({ children }: { children: ReactNode }) {
  const bridge = useBridge();
  const [reducedMotion, setReducedMotion] = useState(false);
  const [assistantName, setAssistantName] = useState(DEFAULT_ASSISTANT_NAME);
  const [modeColors, setModeColors] = useState<Readonly<Record<string, string>>>({});
  // A user edit takes precedence over the async seed forever after — the read
  // resolves within a few ms of mount, but these close the race cleanly. One flag
  // per value so touching one never suppresses another's seed.
  const motionTouched = useRef(false);
  const nameTouched = useRef(false);
  const colorsTouched = useRef(false);

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
        if (!colorsTouched.current) {
          setModeColors(settings.modeColors);
        }
      })
      .catch(() => {
        /* A missing read must not gate the UI; keep the safe defaults. */
      });
    return () => {
      active = false;
    };
  }, [bridge]);

  // Live cross-webview sync (NIC-137 follow-up): a `settings.changed` event carries the
  // authoritative persisted state after any write, so a change made in the separate
  // native settings window reflects on the dashboard (and vice versa) without a relaunch.
  // The event is post-persist truth, so it applies regardless of the local user-touched
  // guards (which only protect against the async startup seed).
  useEffect(() => {
    const unsubscribe = bridge.subscribe((event) => {
      if (event.type !== "settings.changed") {
        return;
      }
      const settings = (event.payload as { settings?: SettingsSnapshot }).settings;
      if (!settings) {
        return;
      }
      setReducedMotion(settings.appearance.reducedMotion);
      setAssistantName(settings.appearance.assistantName);
      setModeColors(settings.modeColors);
    });
    return unsubscribe;
  }, [bridge]);

  // Apply the per-mode overrides by setting the matching `--ch-mode-*` custom properties
  // on the document root; the cleanup clears them so a removed/changed override never lingers.
  useEffect(() => {
    const root = document.documentElement;
    for (const [tokenName, hex] of Object.entries(modeColors)) {
      root.style.setProperty(modeTokenCssVar(tokenName), hex);
    }
    return () => {
      for (const tokenName of Object.keys(modeColors)) {
        root.style.removeProperty(modeTokenCssVar(tokenName));
      }
    };
  }, [modeColors]);

  const setReducedMotionFromUser = useCallback((value: boolean) => {
    motionTouched.current = true;
    setReducedMotion(value);
  }, []);

  const setAssistantNameFromUser = useCallback((value: string) => {
    nameTouched.current = true;
    setAssistantName(value);
  }, []);

  const setModeColorFromUser = useCallback((tokenName: string, hex: string) => {
    colorsTouched.current = true;
    setModeColors((prev) => ({ ...prev, [tokenName]: hex }));
  }, []);

  const value = useMemo<AppearanceController>(
    () => ({
      reducedMotion,
      setReducedMotion: setReducedMotionFromUser,
      assistantName,
      setAssistantName: setAssistantNameFromUser,
      modeColors,
      setModeColor: setModeColorFromUser
    }),
    [
      reducedMotion,
      setReducedMotionFromUser,
      assistantName,
      setAssistantNameFromUser,
      modeColors,
      setModeColorFromUser
    ]
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
