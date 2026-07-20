import { SchedulePanel } from "./SchedulePanel";
import { SystemHealthPanel } from "./SystemHealthPanel";
import { NewsPanel } from "./NewsPanel";
import { WidgetSlot } from "./WidgetSlot";
import { useDashboardState } from "../state/DashboardStateProvider";
import { useActiveMode } from "./useActiveMode";
import { resolveWidgetData } from "../widgets/widgetData";

/**
 * The left information rail (constitution §6 / design spec §5.3): L1 Today, L2 System Health,
 * L3 free widget, L4 News — all bound to the active mode's region data from bootstrap, with
 * no per-mode conditional (NIC-54). The widget slot is registry-driven by widget id.
 */
export function LeftRail() {
  const { regions, liveWidgets } = useDashboardState();
  const activeMode = useActiveMode();

  // The left slot resolves the live-streamed widget for this mode's assigned id over the
  // bootstrap value (NIC-131 blueprint); today no left widget has a producer, so it falls
  // through to the bootstrap value unchanged.
  const leftWidget = resolveWidgetData(liveWidgets, activeMode.widgets.left, regions.widgets.left);

  // tabIndex makes the scrollable rail keyboard-reachable (it has no focusable children of its own,
  // unlike the operations rail); the rail only scrolls as a fallback on very short screens. This is
  // the WCAG-recommended pattern for a scrollable region, so the non-interactive-tabindex rule is
  // intentionally suppressed here.
  return (
    // eslint-disable-next-line jsx-a11y/no-noninteractive-tabindex
    <aside className="shell-rail shell-left" aria-label="Information" tabIndex={0}>
      <SchedulePanel />
      <SystemHealthPanel />
      <WidgetSlot data={leftWidget} labelId="region-widget-left" />
      <NewsPanel />
    </aside>
  );
}
