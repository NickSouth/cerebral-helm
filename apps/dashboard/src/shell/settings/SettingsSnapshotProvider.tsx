import { createContext, useContext, useEffect, useState, type ReactNode } from "react";
import { useBridge } from "../../state/BridgeProvider";
import type { SettingsSnapshot } from "../../bridge/cerebralBridge";

/**
 * The persisted settings the settings window reads once on open so its controls
 * initialize from stored state instead of hardcoded defaults (NIC-141). The read is
 * on demand over the bridge — the main dashboard never needs these values, only the
 * settings surface, so they are deliberately kept out of the bootstrap payload.
 *
 * `loading` until the read resolves, then `ready` with the snapshot, or `error` (a
 * local read failing is rare) with a null snapshot so consumers fall back to their
 * defaults rather than hang. Panels seed their controls from `snapshot` and gate on
 * `status` so a wrong default is never shown as a committable value (the settings
 * window is the only place these are edited).
 */
type SettingsSnapshotState =
  | { readonly status: "loading"; readonly snapshot: null }
  | { readonly status: "ready"; readonly snapshot: SettingsSnapshot }
  | { readonly status: "error"; readonly snapshot: null };

const SettingsSnapshotContext = createContext<SettingsSnapshotState | null>(null);

export function SettingsSnapshotProvider({ children }: { children: ReactNode }) {
  const bridge = useBridge();
  const [state, setState] = useState<SettingsSnapshotState>({ status: "loading", snapshot: null });

  useEffect(() => {
    let active = true;
    bridge
      .getSettings()
      .then((snapshot) => {
        if (active) {
          setState({ status: "ready", snapshot });
        }
      })
      .catch(() => {
        if (active) {
          setState({ status: "error", snapshot: null });
        }
      });
    return () => {
      active = false;
    };
  }, [bridge]);

  return (
    <SettingsSnapshotContext.Provider value={state}>{children}</SettingsSnapshotContext.Provider>
  );
}

export function useSettingsSnapshot(): SettingsSnapshotState {
  const state = useContext(SettingsSnapshotContext);
  if (state === null) {
    throw new Error("useSettingsSnapshot must be used within a SettingsSnapshotProvider.");
  }
  return state;
}
