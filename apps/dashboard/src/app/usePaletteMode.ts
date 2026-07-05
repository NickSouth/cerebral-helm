import { useEffect, useState } from "react";
import { toModeId, type ModeId } from "../tokens/tokens";
import type { CerebralBridge } from "../bridge/cerebralBridge";

interface PaletteModeWindow extends Window {
  __cerebralBootstrap?: { mode?: string };
}

/**
 * Keeps the command palette themed to the active mode (NIC-76 increment 3). Seeds from the
 * bootstrap the native shell injects (`window.__cerebralBootstrap.mode`) and updates on each
 * `config.changed` the coordinator forwards to the palette webview. Extracted as a hook so
 * the sync is unit-testable with a fake bridge (the palette's real bridge is module-scoped).
 */
export function usePaletteMode(bridge: Pick<CerebralBridge, "subscribe"> | null): ModeId {
  const [mode, setMode] = useState<ModeId>(() =>
    toModeId((window as PaletteModeWindow).__cerebralBootstrap?.mode ?? "executive")
  );

  useEffect(() => {
    if (!bridge) {
      return;
    }
    return bridge.subscribe((event) => {
      if (event.type !== "config.changed") {
        return;
      }
      const snapshotMode = (event.payload as { snapshot?: { mode?: string } }).snapshot?.mode;
      if (snapshotMode) {
        setMode(toModeId(snapshotMode));
      }
    });
  }, [bridge]);

  return mode;
}
