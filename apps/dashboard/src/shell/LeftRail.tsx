import { SchedulePanel } from "./SchedulePanel";
import { SystemHealthPanel } from "./SystemHealthPanel";
import { NewsPanel } from "./NewsPanel";
import { WidgetSlot } from "./WidgetSlot";
import { useDashboardState } from "../state/DashboardStateProvider";

/**
 * The left information rail (constitution §6 / design spec §5.3): L1 Today, L2 System Health,
 * L3 free widget, L4 News — all bound to the active mode's region data from bootstrap, with
 * no per-mode conditional (NIC-54). The widget slot is registry-driven by widget id.
 */
export function LeftRail() {
  const { regions } = useDashboardState();

  return (
    <aside className="shell-rail shell-left" aria-label="Information">
      <SchedulePanel />
      <SystemHealthPanel />
      <WidgetSlot data={regions.widgets.left} labelId="region-widget-left" />
      <NewsPanel />
    </aside>
  );
}
