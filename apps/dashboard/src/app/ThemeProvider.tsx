import type { ReactNode } from "react";
import { toModeId } from "../tokens/tokens";
import { useDashboardMode } from "../state/DashboardStateProvider";
import { useAppearance } from "../state/AppearanceProvider";
import { useSurfaceReceded } from "../state/surfacePresence";

/**
 * The single place mode + appearance become visual theme: reads the active mode and applies it once
 * via `data-mode`, applies the reduced-motion override via `data-reduced-motion`, and applies the
 * backdrop posture via `data-receded` (NIC-152). No component re-derives mode color, motion state,
 * or presence (NIC-51 AC-1; NIC-63) — each is one attribute the stylesheet reads.
 */
export function ThemeProvider({ children }: { children: ReactNode }) {
  const modeId = toModeId(useDashboardMode());
  const { reducedMotion } = useAppearance();
  const receded = useSurfaceReceded();

  return (
    <div
      className="app-root"
      data-mode={modeId}
      data-reduced-motion={reducedMotion || undefined}
      data-receded={receded || undefined}
    >
      {children}
    </div>
  );
}
