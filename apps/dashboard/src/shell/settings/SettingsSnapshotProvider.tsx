import { createContext, useContext, useEffect, useState, type ReactNode } from "react";
import { useBridge } from "../../state/BridgeProvider";
import type { SettingsSnapshot } from "../../bridge/cerebralBridge";

/**
 * The persisted settings the settings window reads on open so its controls
 * initialize from stored state instead of hardcoded defaults (NIC-141). The read is
 * on demand over the bridge — the main dashboard never needs these values, only the
 * settings surface, so they are deliberately kept out of the bootstrap payload.
 *
 * `loading` until the read resolves, then `ready` with the snapshot, or `error` (a
 * local read failing is rare) with a null snapshot so consumers fall back to their
 * defaults rather than hang. Panels seed their controls from `snapshot` and gate on
 * `status` so a wrong default is never shown as a committable value (the settings
 * window is the only place these are edited).
 *
 * The snapshot also **follows `settings.changed`** (NIC-176). `updateSettings` emits that
 * event carrying the full resolved snapshot, so subscribing keeps this provider current
 * after every write — including the window's own. Without it, a control rendered directly
 * off `snapshot` with no local state (the calendar→mode `<select>`) re-rendered from the
 * stale read and visibly reverted the user's choice, even though the write had persisted.
 * The same subscription keeps a second surface in step when settings are edited elsewhere.
 */
type SettingsSnapshotState =
  | { readonly status: "loading"; readonly snapshot: null }
  | { readonly status: "ready"; readonly snapshot: SettingsSnapshot }
  | { readonly status: "error"; readonly snapshot: null };

const SettingsSnapshotContext = createContext<SettingsSnapshotState | null>(null);

/**
 * The settings payload of a `settings.changed` event, or null when it is not a well-formed
 * snapshot. A malformed payload leaves the current snapshot alone rather than clearing it —
 * the same "never fabricate, never destroy on a bad payload" guard the live-widget reducers
 * use. `schemaVersion` is the cheapest structural proof that this is a snapshot at all.
 */
function readSnapshot(payload: Readonly<Record<string, unknown>>): SettingsSnapshot | null {
  const settings = (payload as { readonly settings?: unknown }).settings;
  if (typeof settings !== "object" || settings === null) {
    return null;
  }
  if (typeof (settings as { readonly schemaVersion?: unknown }).schemaVersion !== "string") {
    return null;
  }
  return settings as SettingsSnapshot;
}

export function SettingsSnapshotProvider({ children }: { children: ReactNode }) {
  const bridge = useBridge();
  const [state, setState] = useState<SettingsSnapshotState>({ status: "loading", snapshot: null });

  useEffect(() => {
    let active = true;
    // A live event supersedes the initial read. If a write lands while the read is still in
    // flight (this window's own first edit, or another surface's), the slower read resolves
    // with pre-write values and must not clobber the newer snapshot.
    let superseded = false;

    const unsubscribe = bridge.subscribe((event) => {
      if (!active || event.type !== "settings.changed") {
        return;
      }
      const snapshot = readSnapshot(event.payload);
      if (!snapshot) {
        return;
      }
      superseded = true;
      setState({ status: "ready", snapshot });
    });

    bridge
      .getSettings()
      .then((snapshot) => {
        if (active && !superseded) {
          setState({ status: "ready", snapshot });
        }
      })
      .catch(() => {
        if (active && !superseded) {
          setState({ status: "error", snapshot: null });
        }
      });

    return () => {
      active = false;
      unsubscribe();
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
