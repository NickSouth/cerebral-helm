import type { ReactNode } from "react";
import { toModeId } from "../tokens/tokens";
import { useDashboardMode } from "../state/DashboardStateProvider";
import { useAppearance } from "../state/AppearanceProvider";

/**
 * The single place mode + appearance become visual theme: reads the active mode and applies it once
 * via `data-mode`, and applies the reduced-motion override via `data-reduced-motion`. No component
 * re-derives mode color or motion state (NIC-51 AC-1; NIC-63).
 */
export function ThemeProvider({ children }: { children: ReactNode }) {
  const modeId = toModeId(useDashboardMode());
  const { reducedMotion } = useAppearance();

  return (
    <div className="app-root" data-mode={modeId} data-reduced-motion={reducedMotion || undefined}>
      {children}
    </div>
  );
}
