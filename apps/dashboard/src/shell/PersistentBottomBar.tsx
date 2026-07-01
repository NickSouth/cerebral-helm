import { useDashboardState } from "../state/DashboardStateProvider";
import { heimlichStateLabel } from "./labels";
import { BatteryGlyph } from "./BatteryGlyph";
import { WeatherGlyph } from "./WeatherGlyph";
import { HealthGlyph } from "./HealthGlyph";

/** Format the wall clock for display. Masked in visual snapshots (see shell.spec.ts) so the
 *  live value never makes the deterministic baseline flake. */
function formatClock(now: Date): string {
  return now.toLocaleString(undefined, { weekday: "short", hour: "2-digit", minute: "2-digit" });
}

/** A thin vertical rule between bottom-bar groups. */
function Divider() {
  return <span className="bottom-bar__divider" aria-hidden="true" />;
}

/** Gear glyph for the Settings control — Lucide "settings" (ISC-licensed), renders cleanly at any size. */
function SettingsGlyph() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false">
      <path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z" />
      <circle cx="12" cy="12" r="3" />
    </svg>
  );
}

/** Circular Heimlich identity mark — a helm/ship's-wheel placeholder (NIC-118 supplies the final logo). */
function HeimlichMark() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false">
      <circle cx="12" cy="12" r="9" />
      <circle cx="12" cy="12" r="2.6" />
      <path d="M12 3v3.6M12 17.4V21M3 12h3.6M17.4 12H21M5.64 5.64l2.55 2.55M15.81 15.81l2.55 2.55M18.36 5.64l-2.55 2.55M8.19 15.81l-2.55 2.55" />
    </svg>
  );
}

/** Circular sound-wave mark — the ambient audio indicator from the reference. */
function WaveformMark() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" aria-hidden="true" focusable="false">
      <circle cx="12" cy="12" r="9" />
      <path d="M7.5 11v2M9.75 9v6M12 7.5v9M14.25 9v6M16.5 11v2" />
    </svg>
  );
}

/** Heimlich status dot color mirrors the runtime state (idle reads as ready/online, green). */
const HEIMLICH_STATE_DOT: Readonly<Record<string, string>> = {
  idle: "ready",
  listening: "info",
  thinking: "info",
  acting: "warning",
  awaiting_confirmation: "warning",
  success: "ready",
  error: "error",
  offline: "neutral"
};

/**
 * The thin, persistent bottom bar on its own layout track (design spec §5.12, constitution §6).
 * Left→right: Heimlich identity + state · weather (icon + temperature) · [centered] mode · battery
 * (fill icon) · date & time · settings. The bar takes the **active mode accent on the home
 * dashboard only**. Detailed CPU/memory/network metrics live in the System Health widget; the bar
 * keeps only the ambient glanceable status. Weather and battery are mocked pre-Mac; Settings is
 * honest-disabled until its surface lands.
 */
export function PersistentBottomBar({ now = new Date() }: { now?: Date } = {}) {
  const state = useDashboardState();
  const { mode, heimlich, weather } = state;
  const battery = state.regions.systemHealth.battery;

  const weatherLive = weather !== undefined && (weather.state === "ready" || weather.state === "stale");
  const batteryLive = (battery.state === "ready" || battery.state === "stale") && typeof battery.percent === "number";

  return (
    <footer className="bottom-bar shell-bottombar" aria-label="Status bar">
      <div className="bottom-bar__group bottom-bar__group--left">
        <span className="bottom-bar__identity">
          <span className="bottom-bar__avatar" aria-hidden="true">
            <HeimlichMark />
          </span>
          <span className="bottom-bar__identity-text">
            <span className="bottom-bar__name">Heimlich</span>
            <span className="bottom-bar__status">
              <span className="bottom-bar__status-dot" data-state={HEIMLICH_STATE_DOT[heimlich.state] ?? "neutral"} aria-hidden="true" />
              {heimlichStateLabel(heimlich.state)}
            </span>
          </span>
          <span className="bottom-bar__wave" aria-hidden="true">
            <WaveformMark />
          </span>
        </span>

        <Divider />

        {weatherLive ? (
          <span className="bottom-bar__item bottom-bar__weather" title={weather.label}>
            {weather.condition ? <WeatherGlyph condition={weather.condition} /> : null}
            {typeof weather.temperatureF === "number" ? <span>{weather.temperatureF}°F</span> : <span>{weather.label}</span>}
          </span>
        ) : (
          <span className="bottom-bar__item unavailable" title="Weather — requires the macOS host">
            Weather · Unavailable
          </span>
        )}
      </div>

      <div className="bottom-bar__group bottom-bar__group--center">
        {/* Mode accent on the home dashboard only (design spec §5.12); themed via data-mode. */}
        <span className="bottom-bar__item bottom-bar__mode">{mode}</span>
      </div>

      <div className="bottom-bar__group bottom-bar__group--right">
        <span className="bottom-bar__item bottom-bar__wifi" role="img" title="Wi-Fi connected" aria-label="Wi-Fi connected">
          <HealthGlyph name="network" />
        </span>

        {batteryLive ? (
          <span className="bottom-bar__item bottom-bar__battery" role="img" title={battery.label} aria-label={`Battery ${battery.percent}%`}>
            <BatteryGlyph percent={battery.percent as number} />
          </span>
        ) : (
          <span className="bottom-bar__item unavailable" title={battery.label}>
            Battery · Unavailable
          </span>
        )}

        <Divider />

        <span className="bottom-bar__item bottom-bar__clock" aria-label="Date and time">
          {formatClock(now)}
        </span>

        <Divider />

        <button
          type="button"
          className="bottom-bar__control bottom-bar__control--icon"
          disabled
          aria-disabled="true"
          aria-label="Settings"
          title="The settings window arrives in a later increment"
        >
          <SettingsGlyph />
        </button>
      </div>
    </footer>
  );
}
