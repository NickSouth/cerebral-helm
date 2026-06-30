import { Panel } from "./Panel";
import { WidgetSlot } from "./WidgetSlot";
import { useDashboardState } from "../state/DashboardStateProvider";
import { agentActivityLabel } from "./labels";

/**
 * The right operational rail (constitution §6 / design spec §5.9–§5.11): R1 Mode Switcher
 * (4 fixed controls, strong selected state), R2 Agents (the fixed roster with runtime
 * status), R3 free widget. The mode switcher's `applyMode` wiring is NIC-54/D2; the agent
 * workspace that covers this rail on expand is NIC-61 (course-correction A.2).
 */
export function RightRail() {
  const { mode, modes, agents, regions } = useDashboardState();

  return (
    <aside className="shell-rail shell-right" aria-label="Operations">
      <Panel label="Mode" labelId="region-mode">
        <div className="mode-switcher" role="group" aria-labelledby="region-mode">
          {modes.map((modeView) => {
            const active = modeView.label === mode;
            return (
              <button
                key={modeView.id}
                type="button"
                className="mode-switcher__option"
                data-active={active}
                aria-pressed={active}
              >
                {modeView.label}
              </button>
            );
          })}
        </div>
      </Panel>

      <Panel label="Agents" labelId="region-agents">
        <ul className="agent-list">
          {agents.map((agent) => (
            <li key={agent.id} className="agent-list__item">
              <span className="agent-list__name">{agent.label}</span>
              <span className="agent-list__status">{agentActivityLabel(agent.activity)}</span>
            </li>
          ))}
        </ul>
      </Panel>

      <WidgetSlot data={regions.widgets.right} labelId="region-widget-right" />
    </aside>
  );
}
