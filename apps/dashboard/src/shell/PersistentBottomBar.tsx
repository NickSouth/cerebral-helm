import { useEffect, useRef, useState } from "react";
import { useDashboardState } from "../state/DashboardStateProvider";
import { useSettings } from "../state/SettingsProvider";
import { useAppearance } from "../state/AppearanceProvider";
import { useBridge } from "../state/BridgeProvider";
import { useUiPosture } from "../state/useUiPosture";
import { armModeWave } from "./modeWave";
import { heimlichStateLabel } from "./labels";
import { BatteryGlyph } from "./BatteryGlyph";
import { BeamOverlay } from "./BeamOverlay";
import { WeatherGlyph } from "./WeatherGlyph";
import { HealthGlyph } from "./HealthGlyph";
import { HeimlichAvatar } from "./HeimlichAvatar";
import { ModeGlyph } from "./ModeGlyph";

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
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.7"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z" />
      <circle cx="12" cy="12" r="3" />
    </svg>
  );
}

/** Circular sound-wave mark — the ambient audio indicator from the reference. */
function WaveformMark() {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      aria-hidden="true"
      focusable="false"
    >
      <circle cx="12" cy="12" r="9" />
      <path d="M7.5 11v2M9.75 9v6M12 7.5v9M14.25 9v6M16.5 11v2" />
    </svg>
  );
}

/** Heimlich status dot color mirrors the runtime state. At rest (idle) it reads grey/neutral —
 *  the "Not implemented" MVP state (NIC-124) — and only lights up while a command runs. */
const HEIMLICH_STATE_DOT: Readonly<Record<string, string>> = {
  idle: "neutral",
  listening: "info",
  thinking: "info",
  acting: "warning",
  awaiting_confirmation: "warning",
  success: "ready",
  error: "error",
  offline: "neutral"
};

/**
 * The centered mode control in the bottom bar (NIC-77): shows the active mode and opens an
 * upward menu of all four modes. Selecting a mode switches it and — like the right-rail switcher —
 * emits the mode wave, here originating from the bottom-middle control instead of the top-right.
 * Mode switching is paused while the dashboard is read-only, matching the rail switcher.
 */
function BottomBarModeMenu() {
  const { mode, modes } = useDashboardState();
  const bridge = useBridge();
  const { readOnly } = useUiPosture();
  const [open, setOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!open) {
      return;
    }
    function onDocPointerDown(event: MouseEvent): void {
      if (!containerRef.current?.contains(event.target as Node)) {
        setOpen(false);
      }
    }
    function onKeyDown(event: KeyboardEvent): void {
      if (event.key === "Escape") {
        setOpen(false);
      }
    }
    document.addEventListener("mousedown", onDocPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("mousedown", onDocPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [open]);

  function selectMode(modeId: string, active: boolean): void {
    setOpen(false);
    if (active || readOnly) {
      return;
    }
    // Pulse from the bottom-middle control's center (the wave engine reveals the new palette
    // outward from here — bottom-up rather than the rail's top-down).
    const rect = triggerRef.current?.getBoundingClientRect();
    if (rect) {
      armModeWave(rect.left + rect.width / 2, rect.top + rect.height / 2);
    }
    void bridge.applyMode({ modeId });
  }

  return (
    <div className="bottom-bar__mode" ref={containerRef}>
      {open ? (
        <ul className="bottom-bar__mode-menu" role="menu" aria-label="Switch mode">
          {modes.map((modeView) => {
            const active = modeView.label === mode;
            return (
              <li key={modeView.id} role="none">
                <button
                  type="button"
                  role="menuitemradio"
                  aria-checked={active}
                  className="bottom-bar__mode-option"
                  data-active={active}
                  disabled={readOnly}
                  onClick={() => selectMode(modeView.id, active)}
                >
                  <span className="bottom-bar__mode-option-icon" aria-hidden="true">
                    <ModeGlyph mode={modeView.id} />
                  </span>
                  {modeView.label}
                </button>
              </li>
            );
          })}
        </ul>
      ) : null}
      <button
        type="button"
        ref={triggerRef}
        className="bottom-bar__item bottom-bar__mode-trigger"
        aria-haspopup="menu"
        aria-expanded={open}
        disabled={readOnly}
        title={
          readOnly ? "Mode switching is paused while the dashboard is read-only" : "Switch mode"
        }
        onClick={() => setOpen((value) => !value)}
      >
        {mode}
      </button>
    </div>
  );
}

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
  const { openSettings } = useSettings();
  const { assistantName } = useAppearance();
  const { heimlich, weather } = state;
  const battery = state.regions.systemHealth.battery;

  const weatherLive =
    weather !== undefined && (weather.state === "ready" || weather.state === "stale");
  const batteryLive =
    (battery.state === "ready" || battery.state === "stale") && typeof battery.percent === "number";

  return (
    <footer className="bottom-bar shell-bottombar" aria-label="Status bar">
      <div className="bottom-bar__group bottom-bar__group--left">
        <span className="bottom-bar__identity">
          <span className="bottom-bar__avatar" aria-hidden="true">
            <HeimlichAvatar />
          </span>
          <span className="bottom-bar__identity-text">
            <span className="bottom-bar__name">{assistantName}</span>
            <span className="bottom-bar__status">
              <span
                className="bottom-bar__status-dot"
                data-state={HEIMLICH_STATE_DOT[heimlich.state] ?? "neutral"}
                aria-hidden="true"
              />
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
            {typeof weather.temperatureF === "number" ? (
              <span>{weather.temperatureF}°F</span>
            ) : (
              <span>{weather.label}</span>
            )}
          </span>
        ) : (
          <span className="bottom-bar__item unavailable" title="Weather — requires the macOS host">
            Weather · Unavailable
          </span>
        )}
      </div>

      <div className="bottom-bar__group bottom-bar__group--center">
        {/* Mode accent on the home dashboard only (design spec §5.12); themed via data-mode.
            Now an upward menu of all four modes (NIC-77). */}
        <BottomBarModeMenu />
      </div>

      <div className="bottom-bar__group bottom-bar__group--right">
        <span
          className="bottom-bar__item bottom-bar__wifi"
          role="img"
          title="Wi-Fi connected"
          aria-label="Wi-Fi connected"
        >
          <HealthGlyph name="network" />
        </span>

        {batteryLive ? (
          <span
            className="bottom-bar__item bottom-bar__battery"
            role="img"
            title={battery.label}
            aria-label={`Battery ${Math.round(battery.percent as number)}%${battery.charging ? ", charging" : battery.pluggedIn ? ", plugged in" : ""}`}
          >
            <BatteryGlyph
              percent={battery.percent as number}
              charging={battery.charging === true || battery.pluggedIn === true}
            />
          </span>
        ) : (
          <span className="bottom-bar__item unavailable" title={battery.label}>
            Battery · Unavailable
          </span>
        )}

        <Divider />

        {/* No aria-label: the visible text ("Wed 04:25 PM") is already the accessible name.
            aria-label on a role-less <span> is prohibited (WCAG 4.1.2) and would replace the
            actual time value with a vaguer label for assistive tech. */}
        <span className="bottom-bar__item bottom-bar__clock">{formatClock(now)}</span>

        <Divider />

        <button
          type="button"
          className="bottom-bar__control bottom-bar__control--icon"
          aria-label="Settings"
          title="Open settings"
          onClick={() => openSettings()}
        >
          <SettingsGlyph />
        </button>
      </div>
      <BeamOverlay />
    </footer>
  );
}
