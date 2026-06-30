import { Panel } from "./Panel";
import { Unavailable } from "../components/Unavailable";
import { useDashboardState } from "../state/DashboardStateProvider";

/** L2 System Health (design spec §5.3): CPU, memory, network; battery is unavailable pre-Mac. */
export function SystemHealthPanel() {
  const { systemHealth } = useDashboardState().regions;
  const live = systemHealth.state === "ready" || systemHealth.state === "stale";

  return (
    <Panel label="System Health" labelId="region-health">
      {live ? (
        <ul className="metrics">
          {typeof systemHealth.cpuPercent === "number" ? (
            <li className="metrics__item">
              <span>CPU</span>
              <span>{systemHealth.cpuPercent}%</span>
            </li>
          ) : null}
          {typeof systemHealth.memoryPercent === "number" ? (
            <li className="metrics__item">
              <span>Memory</span>
              <span>{systemHealth.memoryPercent}%</span>
            </li>
          ) : null}
          {systemHealth.network ? (
            <li className="metrics__item">
              <span>Network</span>
              <span>{systemHealth.network.label}</span>
            </li>
          ) : null}
          <li className="metrics__item">
            <span>Battery</span>
            <span className="unavailable" title={systemHealth.battery.label}>
              Unavailable
            </span>
          </li>
        </ul>
      ) : (
        <Unavailable label="Metrics unavailable" />
      )}
    </Panel>
  );
}
