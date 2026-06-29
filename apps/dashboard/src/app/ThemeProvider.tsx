import type { ReactNode } from "react";
import { toModeId } from "../tokens/tokens";
import { useDashboardMode } from "../state/DashboardStateProvider";

/**
 * The single place mode becomes a visual theme: reads the active mode from dashboard
 * state and applies it once via `data-mode`. No component re-derives mode color, which
 * is the structural guarantee behind NIC-51 AC-1 (no scattered mode-color conditionals).
 */
export function ThemeProvider({ children }: { children: ReactNode }) {
  const modeId = toModeId(useDashboardMode());

  return (
    <div className="app-root" data-mode={modeId}>
      {children}
    </div>
  );
}
