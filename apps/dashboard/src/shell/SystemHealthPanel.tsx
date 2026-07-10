import { Panel } from "./Panel";
import { PanelGlyph } from "./PanelGlyph";
import { HealthGlyph, type HealthGlyphName } from "./HealthGlyph";
import { ChargingBoltGlyph } from "./BatteryGlyph";
import { StaleMarker } from "../components/StaleMarker";
import { SkeletonBone } from "../components/Skeleton";
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
  tone,
  charging = false,
  chargingTitle = "Charging"
}: {
  glyph: "cpu" | "memory" | "battery";
  label: string;
  percent: number;
  tone: string;
  charging?: boolean;
  chargingTitle?: string;
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
      <span className="metric__value">
        {charging ? (
          <span className="metric__charging" title={chargingTitle} role="img" aria-label={chargingTitle}>
            <ChargingBoltGlyph />
          </span>
        ) : null}
        {Math.round(clamped)}%
      </span>
    </li>
  );
}

/** Extract the throughput figure from the network label (fallback when up/down aren't split out). */
function networkMbps(label: string): string | null {
  const match = label.match(/([\d.]+)\s*Mbps/i);
  return match ? match[1] : null;
}

/** The four System Health rows, in order — the fixed shape the skeleton mirrors. */
const HEALTH_ROWS: readonly { glyph: HealthGlyphName; label: string }[] = [
  { glyph: "cpu", label: "CPU" },
  { glyph: "memory", label: "Memory" },
  { glyph: "network", label: "Network" },
  { glyph: "battery", label: "Battery" }
];

/**
 * The loading shape: the real row structure — icon + label down the left — with shimmer
 * bones where the live figures land. Renders instantly on first paint / mode switch so the
 * panel keeps its exact size and metrics fade into place, rather than flashing an
 * "unavailable" state before the first sample arrives (NIC-136). The generalizable pattern
 * for every live widget: give it a same-shape skeleton for its pre-data state.
 */
function SystemHealthSkeleton() {
  return (
    <ul className="metrics" aria-busy="true">
      <li className="sr-only">Loading system metrics…</li>
      {HEALTH_ROWS.map((row) => (
        <li className="metric" key={row.label} aria-hidden="true">
          <span className="metric__icon">
            <HealthGlyph name={row.glyph} />
          </span>
          <span className="metric__label">{row.label}</span>
          <span className="metric-bar">
            <SkeletonBone className="skeleton-bone--bar" />
          </span>
          <SkeletonBone className="skeleton-bone--value" />
        </li>
      ))}
    </ul>
  );
}

/** L2 System Health (design spec §5.2): CPU/memory usage bars, network throughput, battery. */
export function SystemHealthPanel() {
  const dashboard = useDashboardState();
  const { systemHealth } = dashboard.regions;
  const live = systemHealth.state === "ready" || systemHealth.state === "stale";
  // Loading vs genuinely-unavailable: the metrics provider being available means a sample
  // is on its way (first paint, or the pre-sample window after a permission grant), so show
  // the same-shape skeleton instead of the honest-unavailable flash (NIC-136). Only genuine
  // absence — no metrics capability, or an explicit unavailable with none expected — renders
  // Unavailable.
  const metricsExpected = dashboard.capabilities?.["system.metrics"]?.available === true;
  const loading = !live && (systemHealth.state === "empty" || metricsExpected);
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
                  <span className="metric__value">{Math.round(network.uploadMbps)} Mbps</span>
                  <span className="net-arrow net-arrow--down" aria-hidden="true">
                    ↓
                  </span>
                  <span className="metric__value">{Math.round(network.downloadMbps)} Mbps</span>
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
              charging={battery.charging === true || battery.pluggedIn === true}
              chargingTitle={battery.charging === true ? "Charging" : "Plugged in"}
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
      ) : loading ? (
        <SystemHealthSkeleton />
      ) : (
        <Unavailable label="Metrics unavailable" />
      )}
    </Panel>
  );
}
