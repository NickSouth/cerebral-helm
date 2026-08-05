import { AgentGlyph } from "./AgentGlyph";
import { useDashboardState } from "../state/DashboardStateProvider";
import { agentActivityLabel } from "./labels";

/**
 * The fixed agent roster with runtime status (design spec §5.10), extracted from `RightRail` so
 * the edge sidebar shows the same roster and the same live activity rather than a second copy.
 * The rail wraps this in its `Panel`; the sidebar renders it bare.
 */
export function AgentRoster() {
  const { agents } = useDashboardState();

  return (
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
  );
}
