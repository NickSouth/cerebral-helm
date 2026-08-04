import { Panel } from "./Panel";
import { PanelGlyph } from "./PanelGlyph";
import { ModeSwitcher } from "./ModeSwitcher";
import { AgentRoster } from "./AgentRoster";
import { WidgetSlot } from "./WidgetSlot";
import { useDashboardState } from "../state/DashboardStateProvider";
import { useActiveMode } from "./useActiveMode";
import { resolveWidgetData } from "../widgets/widgetData";

/**
 * The right operational rail (constitution §6 / design spec §5.9–§5.11): R1 Mode Switcher
 * (4 fixed controls, strong selected state), R2 Agents (the fixed roster with runtime
 * status), R3 free widget. The mode switcher's `applyMode` wiring is NIC-54/D2; the agent
 * workspace that covers this rail on expand is NIC-61 (course-correction A.2).
 *
 * The switcher and roster live in their own components because the edge sidebar renders the
 * same two controls without this rail's panel chrome — one control, two hosts, no fork.
 */
export function RightRail() {
  const { regions, liveWidgets } = useDashboardState();
  const activeMode = useActiveMode();

  // Resolve the right slot: the live-streamed widget for this mode's assigned id
  // (NIC-131 blueprint) over the bootstrap value. Every future live widget inherits this.
  const rightWidget = resolveWidgetData(liveWidgets, activeMode.widgets.right, regions.widgets.right);

  return (
    <aside className="shell-rail shell-right" aria-label="Operations">
      <Panel label="Mode" labelId="region-mode" icon={<PanelGlyph name="mode" />}>
        <ModeSwitcher labelledBy="region-mode" />
      </Panel>

      <Panel label="Agents" labelId="region-agents" icon={<PanelGlyph name="agents" />}>
        <AgentRoster />
      </Panel>

      <WidgetSlot data={rightWidget} labelId="region-widget-right" slotWidgetId={activeMode.widgets.right} />
    </aside>
  );
}
