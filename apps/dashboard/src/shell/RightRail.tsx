import { Panel } from "./Panel";
import { PanelGlyph } from "./PanelGlyph";
import { ModeGlyph } from "./ModeGlyph";
import { AgentGlyph } from "./AgentGlyph";
import { WidgetSlot } from "./WidgetSlot";
import { useDashboardState } from "../state/DashboardStateProvider";
import { useBridge } from "../state/BridgeProvider";
import { useUiPosture } from "../state/useUiPosture";
import { agentActivityLabel } from "./labels";
import { armModeWave } from "./modeWave";

/**
 * The right operational rail (constitution §6 / design spec §5.9–§5.11): R1 Mode Switcher
 * (4 fixed controls, strong selected state), R2 Agents (the fixed roster with runtime
 * status), R3 free widget. The mode switcher's `applyMode` wiring is NIC-54/D2; the agent
 * workspace that covers this rail on expand is NIC-61 (course-correction A.2).
 */
export function RightRail() {
  const { mode, modes, agents, regions } = useDashboardState();
  const bridge = useBridge();
  const { readOnly } = useUiPosture();

  return (
    <aside className="shell-rail shell-right" aria-label="Operations">
      <Panel label="Mode" labelId="region-mode" icon={<PanelGlyph name="mode" />}>
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
                disabled={readOnly}
                aria-disabled={readOnly || undefined}
                title={readOnly ? "Mode switching is paused while the dashboard is read-only" : undefined}
                onClick={(event) => {
                  if (!active && !readOnly) {
                    // Arm the mode wave from this control's center: the theme change propagates
                    // outward from where the user clicked (shell/modeWave.ts).
                    const rect = event.currentTarget.getBoundingClientRect();
                    armModeWave(rect.left + rect.width / 2, rect.top + rect.height / 2);
                    void bridge.applyMode({ modeId: modeView.id });
                  }
                }}
              >
                <span className="mode-switcher__icon">
                  <ModeGlyph mode={modeView.id} />
                </span>
                <span className="mode-switcher__label">{modeView.label}</span>
              </button>
            );
          })}
        </div>
      </Panel>

      <Panel label="Agents" labelId="region-agents" icon={<PanelGlyph name="agents" />}>
        <ul className="agent-list">
          {agents.map((agent) => (
            <li key={agent.id} className="agent-list__item">
              <span className="agent-avatar" data-agent={agent.id} aria-hidden="true">
                <AgentGlyph agentId={agent.id} />
              </span>
              <span className="agent-list__name">{agent.label}</span>
              <span className="agent-list__status">
                <span className="agent-status-dot" data-activity={agent.activity} aria-hidden="true" />
                {agentActivityLabel(agent.activity)}
              </span>
            </li>
          ))}
        </ul>
      </Panel>

      <WidgetSlot data={regions.widgets.right} labelId="region-widget-right" />
    </aside>
  );
}
