import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { Panel } from "./Panel";
import { PanelGlyph } from "./PanelGlyph";
import { HealthGlyph, signalLevelFromRssi, type HealthGlyphName } from "./HealthGlyph";
import { ChargingBoltGlyph } from "./BatteryGlyph";
import { StaleMarker } from "../components/StaleMarker";
import { SkeletonBone } from "../components/Skeleton";
import { Unavailable } from "../components/Unavailable";
import { useDashboardState } from "../state/DashboardStateProvider";
import { useBridge } from "../state/BridgeProvider";
import type { SpeedTestResult } from "../bridge/cerebralBridge";
import type { WiFiPower } from "../bridge/types";

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

/** A one-decimal Mbps figure, or an em dash when a direction wasn't measured. */
function fmtMbps(value?: number): string {
  return typeof value === "number" ? value.toFixed(value >= 100 ? 0 : 1) : "—";
}

/**
 * The progress ring for the on-demand speed test (NIC-135). networkQuality reports
 * no incremental progress, so the ring fills over the run's bounded duration
 * (~30s, the -M cap) and snaps to full the instant the real result lands — an
 * honest "working" indicator, not a fake percentage.
 */
function SpeedRing({ phase }: { phase: "idle" | "measuring" | "done" }) {
  return (
    <svg className="netspeed__ring" data-phase={phase} viewBox="0 0 40 40" width="40" height="40" aria-hidden="true">
      <circle className="netspeed__ring-track" cx="20" cy="20" r="15" fill="none" strokeWidth="3" />
      <circle className="netspeed__ring-fill" cx="20" cy="20" r="15" fill="none" strokeWidth="3" />
    </svg>
  );
}

/**
 * The Network row: Wi-Fi glyph · link speed (NIC-135) · a wedge that expands an
 * inline speed-test panel on the dashboard backdrop (never its own window). The
 * "Test" button runs the read-only `network.speed.test` tool via the bridge and
 * shows the last download/upload result, cached for the session.
 */
function NetworkRow({
  linkMbps,
  wifiPower,
  signalRssi
}: {
  linkMbps?: number;
  wifiPower?: WiFiPower;
  signalRssi?: number;
}) {
  const bridge = useBridge();
  const toggleRef = useRef<HTMLButtonElement>(null);
  const popoverRef = useRef<HTMLDivElement>(null);
  const [expanded, setExpanded] = useState(false);
  const [anchor, setAnchor] = useState<{ left: number; top: number } | null>(null);
  const [phase, setPhase] = useState<"idle" | "measuring" | "done">("idle");
  const [result, setResult] = useState<SpeedTestResult | null>(null);

  // The popover floats to the RIGHT of the row, overlapping the centre panel, so
  // opening it never grows the System Health panel or clips the widgets below it.
  // It's a portal at a fixed, measured position — panels use overflow:hidden and
  // backdrop-filter, either of which would otherwise trap or clip it.
  function toggle() {
    setExpanded((open) => {
      if (open) return false;
      const rect = toggleRef.current?.getBoundingClientRect();
      if (rect) {
        // Prefer the right of the row (overlapping the centre panel); clamp so a
        // narrow viewport can't push the callout off-screen.
        const POPOVER_WIDTH = 176;
        const left = Math.min(rect.right + 10, Math.max(8, window.innerWidth - POPOVER_WIDTH - 8));
        setAnchor({ left, top: rect.top + rect.height / 2 });
      }
      return true;
    });
  }

  // Dismiss on an outside click — but never when the click is the toggle or lands
  // inside the popover itself (so pressing Test does not close it).
  useEffect(() => {
    if (!expanded) return;
    function onPointerDown(event: MouseEvent) {
      const target = event.target as Node;
      if (popoverRef.current?.contains(target) || toggleRef.current?.contains(target)) return;
      setExpanded(false);
    }
    document.addEventListener("mousedown", onPointerDown);
    return () => document.removeEventListener("mousedown", onPointerDown);
  }, [expanded]);

  async function runTest() {
    if (phase === "measuring") return;
    setPhase("measuring");
    try {
      setResult(await bridge.runSpeedTest());
    } catch {
      setResult({ status: "unavailable" });
    } finally {
      setPhase("done");
    }
  }

  const measuring = phase === "measuring";

  return (
    <li className="metric metric--network">
      <span className="metric__icon">
        <HealthGlyph
          name={wifiPower === "off" || wifiPower === "absent" ? "network-off" : "network"}
          signalLevel={signalLevelFromRssi(signalRssi)}
        />
      </span>
      <span className="metric__label">Network</span>
      {typeof linkMbps === "number" ? (
        <span className="metric__value metric__value--network">{Math.round(linkMbps)} Mbps</span>
      ) : (
        <span className="unavailable metric__unavailable metric__value--network">
          {wifiPower === "off" ? "Wi-Fi off" : "No Wi-Fi"}
        </span>
      )}
      <button
        ref={toggleRef}
        type="button"
        className="netspeed__toggle"
        data-open={expanded ? "true" : undefined}
        aria-expanded={expanded}
        aria-controls="netspeed-panel"
        aria-label={expanded ? "Hide speed test" : "Show speed test"}
        onClick={toggle}
      >
        <svg className="netspeed__wedge" viewBox="0 0 16 16" width="13" height="13" aria-hidden="true">
          <path d="M6 4l4 4-4 4" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>
      {expanded && anchor
        ? createPortal(
            <div
              ref={popoverRef}
              id="netspeed-panel"
              className="netspeed"
              role="group"
              aria-label="Speed test"
              style={{ left: anchor.left, top: anchor.top }}
            >
              <div className="netspeed__ring-wrap" aria-hidden="true">
                <SpeedRing phase={phase} />
              </div>
              <div className="netspeed__readout" aria-live="polite">
                {phase === "done" && result ? (
                  result.status === "unavailable" ? (
                    <span className="netspeed__note">Speed test unavailable</span>
                  ) : (
                    <div className="netspeed__figures">
                      <span className="netspeed__figure">
                        <span className="netspeed__arrow" aria-hidden="true">↓</span>
                        {fmtMbps(result.downloadMbps)} <span className="netspeed__unit">Mbps</span>
                      </span>
                      <span className="netspeed__figure">
                        <span className="netspeed__arrow" aria-hidden="true">↑</span>
                        {fmtMbps(result.uploadMbps)} <span className="netspeed__unit">Mbps</span>
                      </span>
                    </div>
                  )
                ) : (
                  <span className="netspeed__note">{measuring ? "Measuring…" : "Test your speed"}</span>
                )}
              </div>
              <button type="button" className="netspeed__run" onClick={runTest} disabled={measuring}>
                {measuring ? "Testing…" : result ? "Retest" : "Test"}
              </button>
            </div>,
            document.body
          )
        : null}
    </li>
  );
}

/** L2 System Health (design spec §5.2): CPU/memory usage bars, Wi-Fi link speed, battery. */
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
            <NetworkRow
              linkMbps={network.linkMbps}
              wifiPower={network.wifiPower}
              signalRssi={network.signalRssi}
            />
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
