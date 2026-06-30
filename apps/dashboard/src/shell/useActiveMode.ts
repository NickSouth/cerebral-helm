import { useDashboardState } from "../state/DashboardStateProvider";
import type { ModeView } from "../bridge/types";

/**
 * The resolved config of the currently active mode, taken from the eager `modes` shipped in
 * bootstrap state. This is how the one shared mode view renders all four modes WITHOUT a
 * per-mode conditional (NIC-54): components read the active ModeView, never branch on `mode`.
 */
export function useActiveMode(): ModeView {
  const { mode, modes } = useDashboardState();
  const active = modes.find((modeView) => modeView.label === mode);

  if (!active) {
    throw new Error(`Active mode "${mode}" is not present in bootstrap modes.`);
  }

  return active;
}
