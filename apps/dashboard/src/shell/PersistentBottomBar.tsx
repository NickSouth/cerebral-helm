import { useDashboardState } from "../state/DashboardStateProvider";
import { heimlichStateLabel } from "./labels";
import type { MetricChannel, RegionState } from "../bridge/types";

/** The non-live channel states, as distinct honest words (design spec §5.12, NIC-59). */
const METRIC_STATE_WORD: Readonly<Record<RegionState, string>> = {
  ready: "Live",
  empty: "No data",
  stale: "Stale",
  unavailable: "Disconnected"
};

/** Format the wall clock for display. Masked in visual snapshots (see shell.spec.ts) so the
 *  live value never makes the deterministic baseline flake. */
function formatClock(now: Date): string {
  return now.toLocaleString(undefined, { weekday: "short", hour: "2-digit", minute: "2-digit" });
}

/** A network/Wi-Fi channel, rendered with a state-distinct treatment (its label carries detail). */
function NetworkMetric({ channel }: { channel?: MetricChannel }) {
  if (!channel) {
    return null;
  }
  const cls =
    channel.state === "ready"
      ? ""
      : channel.state === "stale"
        ? " bottom-bar__metric--stale"
        : " unavailable";
  return (
    <span className={`bottom-bar__item${cls}`} title={channel.label}>
      {channel.label}
    </span>
  );
}

/**
 * The thin, persistent bottom bar on its own layout track (design spec §5.12, constitution §6).
 * Left→right: Heimlich identity + state · weather · [centered] mode · Wi-Fi · battery · date &
 * time · settings. The bar takes the **active mode accent on the home dashboard only** (there is
 * no layout mode pre-Mac, so it always applies here); system confirmation surfaces never inherit
 * it. CPU/memory/network reflect `regions.systemHealth` with distinct loading/stale/disconnected
 * states; **weather and battery are honest-unavailable pre-Mac**, and Settings/Emergency are
 * honest-disabled until their surfaces land (NIC-63 / a later increment).
 */
export function PersistentBottomBar({ now = new Date() }: { now?: Date } = {}) {
  const state = useDashboardState();
  const { mode, uiState, heimlich } = state;
  const { systemHealth } = state.regions;

  const loading = uiState === "loading";
  const live = systemHealth.state === "ready" || systemHealth.state === "stale";
  const stale = systemHealth.state === "stale";

  return (
    <footer className="bottom-bar shell-bottombar" aria-label="Status bar">
      <div className="bottom-bar__group bottom-bar__group--left">
        <span className="bottom-bar__item">Heimlich · {heimlichStateLabel(heimlich.state)}</span>
        <span className="bottom-bar__item unavailable" title="Weather — requires the macOS host">
          Weather · Unavailable
        </span>
      </div>

      <div className="bottom-bar__group bottom-bar__group--center">
        {/* Mode accent on the home dashboard only (design spec §5.12); themed via data-mode. */}
        <span className="bottom-bar__item bottom-bar__mode">{mode}</span>
      </div>

      <div className="bottom-bar__group bottom-bar__group--right">
        {loading ? (
          <span className="bottom-bar__item bottom-bar__metric--loading">Metrics · Sampling…</span>
        ) : live ? (
          <>
            {typeof systemHealth.cpuPercent === "number" ? (
              <span className={`bottom-bar__item${stale ? " bottom-bar__metric--stale" : ""}`}>
                CPU {systemHealth.cpuPercent}%{stale ? " · stale" : ""}
              </span>
            ) : null}
            {typeof systemHealth.memoryPercent === "number" ? (
              <span className={`bottom-bar__item${stale ? " bottom-bar__metric--stale" : ""}`}>
                Mem {systemHealth.memoryPercent}%
              </span>
            ) : null}
          </>
        ) : (
          <span className="bottom-bar__item unavailable">Metrics · {METRIC_STATE_WORD[systemHealth.state]}</span>
        )}

        <NetworkMetric channel={systemHealth.network} />

        <span className="bottom-bar__item unavailable" title={systemHealth.battery.label}>
          Battery · Unavailable
        </span>

        <span className="bottom-bar__item bottom-bar__clock" aria-label="Date and time">
          {formatClock(now)}
        </span>

        <button
          type="button"
          className="bottom-bar__control"
          disabled
          aria-disabled="true"
          title="The settings window arrives in a later increment"
        >
          Settings
        </button>
        <button
          type="button"
          className="bottom-bar__control"
          disabled
          aria-disabled="true"
          title="Emergency controls require the macOS host"
        >
          Emergency
        </button>
      </div>
    </footer>
  );
}
