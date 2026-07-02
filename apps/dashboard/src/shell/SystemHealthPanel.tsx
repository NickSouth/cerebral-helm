import { Panel } from "./Panel";
import { PanelGlyph } from "./PanelGlyph";
import { HealthGlyph } from "./HealthGlyph";
import { StaleMarker } from "../components/StaleMarker";
import { Unavailable } from "../components/Unavailable";
import { useDashboardState } from "../state/DashboardStateProvider";

/** Usage-bar tone: mode accent normally, red once a utilization metric crosses 90% (owner rule). */
function usageTone(percent: number): string {
  return percent > 90 ? "danger" : "accent";
}

/** Battery tone (owner rule): green above 60, yellow down to 20, red below 20. */
function batteryTone(percent: number): string {
  if (percent > 60) return "good";
  if (percent >= 20) return "warning";
  return "danger";
}

/** A metric row: category glyph · label · usage bar · right-aligned value. */
function BarRow({
  glyph,
  label,
  percent,
  tone
}: {
  glyph: "cpu" | "memory" | "battery";
  label: string;
  percent: number;
  tone: string;
}) {
  const clamped = Math.max(0, Math.min(100, percent));
  return (
    <li className="metric">
      <span className="metric__icon">
        <HealthGlyph name={glyph} />
      </span>
      <span className="metric__label">{label}</span>
      <span className="metric-bar" aria-hidden="true">
        <span className="metric-bar__fill" data-tone={tone} style={{ width: `${clamped}%` }} />
      </span>
      <span className="metric__value">{percent}%</span>
    </li>
  );
}

/** Extract the throughput figure from the network label (fallback when up/down aren't split out). */
function networkMbps(label: string): string | null {
  const match = label.match(/([\d.]+)\s*Mbps/i);
  return match ? match[1] : null;
}

/** L2 System Health (design spec §5.2): CPU/memory usage bars, network throughput, battery. */
export function SystemHealthPanel() {
  const { systemHealth } = useDashboardState().regions;
  const live = systemHealth.state === "ready" || systemHealth.state === "stale";
  const network = systemHealth.network;
  const battery = systemHealth.battery;
  const batteryLive =
    (battery.state === "ready" || battery.state === "stale") && typeof battery.percent === "number";

  return (
    <Panel label="System Health" labelId="region-health" icon={<PanelGlyph name="system-health" />}>
      {systemHealth.state === "stale" ? <StaleMarker label="Metrics may be out of date" /> : null}
      {live ? (
        <ul className="metrics">
          {typeof systemHealth.cpuPercent === "number" ? (
            <BarRow
              glyph="cpu"
              label="CPU"
              percent={systemHealth.cpuPercent}
              tone={usageTone(systemHealth.cpuPercent)}
            />
          ) : null}
          {typeof systemHealth.memoryPercent === "number" ? (
            <BarRow
              glyph="memory"
              label="Memory"
              percent={systemHealth.memoryPercent}
              tone={usageTone(systemHealth.memoryPercent)}
            />
          ) : null}
          {network ? (
            <li className="metric">
              <span className="metric__icon">
                <HealthGlyph name="network" />
              </span>
              <span className="metric__label">Network</span>
              {typeof network.uploadMbps === "number" &&
              typeof network.downloadMbps === "number" ? (
                <span className="metric__network">
                  <span className="net-arrow net-arrow--up" aria-hidden="true">
                    ↑
                  </span>
                  <span className="metric__value">{network.uploadMbps} Mbps</span>
                  <span className="net-arrow net-arrow--down" aria-hidden="true">
                    ↓
                  </span>
                  <span className="metric__value">{network.downloadMbps} Mbps</span>
                </span>
              ) : networkMbps(network.label) ? (
                <span className="metric__network">
                  <span className="net-arrow net-arrow--up" aria-hidden="true">
                    ↑
                  </span>
                  <span className="metric__value">{networkMbps(network.label)} Mbps</span>
                  <span className="net-arrow net-arrow--down" aria-hidden="true">
                    ↓
                  </span>
                </span>
              ) : (
                <span className="metric__value">{network.label}</span>
              )}
            </li>
          ) : null}
          {batteryLive ? (
            <BarRow
              glyph="battery"
              label="Battery"
              percent={battery.percent as number}
              tone={batteryTone(battery.percent as number)}
            />
          ) : (
            <li className="metric">
              <span className="metric__icon">
                <HealthGlyph name="battery" />
              </span>
              <span className="metric__label">Battery</span>
              {/* Honest-unavailable when no percentage is delivered (Mac-only capability, NIC-117 j). */}
              <span className="unavailable metric__unavailable" title={battery.label}>
                Unavailable
              </span>
            </li>
          )}
        </ul>
      ) : (
        <Unavailable label="Metrics unavailable" />
      )}
    </Panel>
  );
}
