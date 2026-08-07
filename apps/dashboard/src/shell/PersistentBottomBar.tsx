import { useEffect, useRef, useState, type MouseEvent as ReactMouseEvent } from "react";
import { postShellControl } from "./shellControl";
import { useDashboardState } from "../state/DashboardStateProvider";
import { useSettings } from "../state/SettingsProvider";
import { useAppearance } from "../state/AppearanceProvider";
import { useBridge } from "../state/BridgeProvider";
import { useUiPosture } from "../state/useUiPosture";
import type { LayoutSession } from "../state/dashboardState";
import type { NetworkChannel } from "../bridge/types";
import { AppGlyph } from "./AppGlyph";
import { LayoutPinPicker } from "./LayoutPinPicker";
import { useResolvedAppIcons, type ResolvedIcon } from "./useResolvedAppIcons";
import { armModeWave } from "./modeWave";
import { heimlichStateLabel } from "./labels";
import { BatteryGlyph } from "./BatteryGlyph";
import { BeamOverlay } from "./BeamOverlay";
import { WeatherGlyph } from "./WeatherGlyph";
import { HealthGlyph, signalLevelFromRssi } from "./HealthGlyph";
import { HeimlichAvatar } from "./HeimlichAvatar";
import { ModeGlyph } from "./ModeGlyph";
import { WindowNavigator } from "./WindowNavigator";

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

/** Collapse/expand-all glyph (NIC-143): a tray with a down arrow while windows are
 *  shown (press to stow them) and an up arrow while collapsed (press to bring them
 *  back) — the "container" the user tucks their windows into. */
function CollapseGlyph({ collapsed }: { collapsed: boolean }) {
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
      {collapsed ? (
        <>
          <path d="M12 13V4" />
          <path d="M8 8l4-4 4 4" />
        </>
      ) : (
        <>
          <path d="M12 4v9" />
          <path d="M8 9l4 4 4-4" />
        </>
      )}
      <path d="M4 20h16" />
    </svg>
  );
}

/** Close-all-windows glyph (NIC-143): stacked windows with an ×. */
function CloseAllGlyph() {
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
      <path d="M8 5h11a1 1 0 0 1 1 1v9" />
      <rect x="4" y="9" width="12" height="10" rx="1.5" />
      <path d="M8 12.5l4 4M12 12.5l-4 4" />
    </svg>
  );
}

/** Window-navigator glyph (NIC-143): a 2×2 grid of windows, the app-switcher mark. */
function WindowNavigatorGlyph() {
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
      <rect x="4" y="4" width="7" height="7" rx="1.4" />
      <rect x="13" y="4" width="7" height="7" rx="1.4" />
      <rect x="4" y="13" width="7" height="7" rx="1.4" />
      <rect x="13" y="13" width="7" height="7" rx="1.4" />
    </svg>
  );
}

/**
 * The window-management section on the right of the bottom bar (NIC-143), shown whenever
 * layout mode is not open. Three icon-first controls: collapse/expand all of the current
 * mode's windows (the only one wired in this increment), close-all (all modes), and the
 * window navigator. The latter two are honest "coming soon" placeholders until their own
 * increments land. Collapse toggles the current mode's session bucket through the bridge;
 * its icon reflects that mode's live collapsed state.
 */
function WindowManagementSection() {
  const state = useDashboardState();
  const bridge = useBridge();
  const { readOnly } = useUiPosture();
  const [navigatorOpen, setNavigatorOpen] = useState(false);

  const currentModeId = state.modes.find((modeView) => modeView.label === state.mode)?.id;
  const collapsed = currentModeId ? (state.windowCollapse?.[currentModeId] ?? false) : false;

  const onOpenNavigator = (event: ReactMouseEvent<HTMLButtonElement>): void => {
    if (readOnly) {
      return;
    }
    // Prefer the native top-most window so the navigator layers above open windows
    // (the backdrop never lifts). In a plain browser there is no native channel, so
    // fall back to the in-dashboard overlay.
    //
    // The button's viewport rect rides along, the same shape More Apps posts (the backdrop fills
    // the screen, so the shell converts it to screen coordinates). It does not place the window —
    // the navigator stays pinned to the right edge — it tells the shell which direction to open
    // from, so the slab flies out of this control rather than materialising beside it.
    const rect = event.currentTarget.getBoundingClientRect();
    const anchor = { x: rect.left, y: rect.top, width: rect.width, height: rect.height };
    if (!postShellControl("openWindowNavigator", { anchor })) {
      setNavigatorOpen(true);
    }
  };

  const onToggleCollapse = (): void => {
    if (!currentModeId || readOnly) {
      return;
    }
    void bridge.toggleModeCollapse({ modeId: currentModeId });
  };

  const onCloseAll = (): void => {
    if (readOnly) {
      return;
    }
    // Destructive: the command bus gates this on a confirmation before anything quits.
    void bridge.closeAllWindows();
  };

  return (
    <span className="bottom-bar__winmgmt" role="group" aria-label="Window management">
      <button
        type="button"
        className="bottom-bar__control bottom-bar__control--icon"
        aria-label={collapsed ? "Expand all windows" : "Collapse all windows"}
        aria-pressed={collapsed}
        title={
          readOnly
            ? "Window controls are paused while the dashboard is read-only"
            : collapsed
              ? "Bring the collapsed windows back"
              : "Hide all windows in this mode"
        }
        disabled={readOnly || !currentModeId}
        onClick={onToggleCollapse}
      >
        <CollapseGlyph collapsed={collapsed} />
      </button>
      <button
        type="button"
        className="bottom-bar__control bottom-bar__control--icon"
        aria-label="Close all windows"
        title={
          readOnly
            ? "Window controls are paused while the dashboard is read-only"
            : "Close all windows (quits every app — asks first)"
        }
        disabled={readOnly}
        onClick={onCloseAll}
      >
        <CloseAllGlyph />
      </button>
      <button
        type="button"
        className="bottom-bar__control bottom-bar__control--icon"
        aria-label="Open window navigator"
        aria-expanded={navigatorOpen}
        title={
          readOnly
            ? "Window controls are paused while the dashboard is read-only"
            : "Browse open windows"
        }
        disabled={readOnly}
        onClick={onOpenNavigator}
      >
        <WindowNavigatorGlyph />
      </button>
      {navigatorOpen ? (
        <WindowNavigator variant="overlay" onClose={() => setNavigatorOpen(false)} />
      ) : null}
    </span>
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

/** Heimlich status dot color mirrors the runtime state. Today that is always `idle` → grey/neutral,
 *  the "Not implemented" MVP state (NIC-124): the command lifecycle no longer drives the indicator
 *  (NIC-171), so the dot does not light up while a command runs. The other entries are retained,
 *  unreached at runtime, for when a real assistant lands — same reasoning as HEIMLICH_STATE_LABELS. */
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
 * The centered mode control in the bottom bar (NIC-77): shows the active mode and opens a
 * menu of all four modes. In the native shell the menu is a transparent, top-most window
 * that layers ABOVE open apps (NIC-144) — the dashboard is a strict never-lift backdrop,
 * so an in-backdrop menu could be covered. Clicking the trigger posts `openModeMenu` with
 * the control's anchor rect; in a plain browser (no native channel) it falls back to the
 * in-webview upward menu, which also emits the bottom-origin mode wave. Mode switching is
 * paused while the dashboard is read-only, matching the rail switcher.
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

  function toggleMenu(): void {
    if (readOnly) {
      return;
    }
    // Prefer the native top-most dropdown so the menu layers above open windows; pass the
    // trigger's viewport rect so the shell drops it right above the control. Only when no
    // native channel exists (a plain browser) do we fall back to the in-webview menu.
    const rect = triggerRef.current?.getBoundingClientRect();
    const anchor = rect
      ? { x: rect.left, y: rect.top, width: rect.width, height: rect.height }
      : undefined;
    if (postShellControl("openModeMenu", anchor ? { anchor } : {})) {
      return;
    }
    setOpen((value) => !value);
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
        onClick={toggleMenu}
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
/** One hotswap tile in the layout pill: a squircle-masked OS icon / favicon (with a
 *  Chrome-profile badge), or an honest category glyph while discovery loads. Shape
 *  and resolution match a Quick Apps tile exactly (NIC-142). */
function HotswapTileFace({ icon }: { icon: ResolvedIcon }) {
  return (
    <span className="bottom-bar__layout-tile-icon" aria-hidden="true">
      {icon.iconPng ? (
        <img
          className="bottom-bar__layout-tile-img"
          src={`data:image/png;base64,${icon.iconPng}`}
          alt=""
        />
      ) : (
        <AppGlyph category={icon.fallbackCategory} />
      )}
      {icon.profileAvatarPng ? (
        <img
          className="bottom-bar__layout-tile-badge"
          src={`data:image/png;base64,${icon.profileAvatarPng}`}
          alt=""
          aria-hidden="true"
        />
      ) : null}
    </span>
  );
}

/**
 * The layout-mode section (NIC-142): while a layout is active it renders as a single
 * accent pill of the mode's hotswap (quick-toggle) targets — each an app icon / URL
 * favicon (Chrome-profile aware), the active one ringed — followed by a "+" to pin
 * another and a close "×". Static (non-hotswap) windows are not shown; the pill just
 * reads as its own grouped control between weather and the centered mode. Pressing a
 * target swaps the dynamic slot to it (hides the shown one, surfaces the pressed one)
 * — no confirmation, authorized when the layout opened.
 */
function LayoutBar({ session }: { session: LayoutSession }) {
  const bridge = useBridge();
  const toggle = session.quickToggle;
  const resolve = useResolvedAppIcons(toggle?.targets.map((target) => target.ref) ?? []);
  // The "+" opens the native layout-pin window (top-most, above the "+", so it can
  // overlap the open layout windows — the backdrop never lifts). In a plain browser
  // there is no native channel, so it falls back to the in-webview picker overlay.
  const [pickerOpen, setPickerOpen] = useState(false);

  const openPin = (event: ReactMouseEvent<HTMLButtonElement>): void => {
    const rect = event.currentTarget.getBoundingClientRect();
    const anchor = { x: rect.left, y: rect.top, width: rect.width, height: rect.height };
    if (!postShellControl("openLayoutPin", { anchor })) {
      setPickerOpen(true);
    }
  };

  return (
    <div className="bottom-bar__layout" aria-label="Layout windows">
      {toggle
        ? toggle.targets.map((target) => {
            const active = target.ref === toggle.activeRef;
            const icon = resolve(target.ref, target.label);
            return (
              <button
                key={target.ref}
                type="button"
                className="bottom-bar__layout-tile"
                data-active={active ? "true" : undefined}
                aria-pressed={active}
                aria-label={icon.label}
                title={icon.label}
                onClick={() => {
                  void bridge.toggleLayout({ ref: target.ref });
                }}
              >
                <HotswapTileFace icon={icon} />
              </button>
            );
          })
        : null}
      {toggle ? (
        <span className="bottom-bar__layout-add-wrap">
          <button
            type="button"
            className="bottom-bar__layout-add"
            aria-label="Pin a window"
            aria-expanded={pickerOpen}
            onClick={openPin}
          >
            <span aria-hidden="true">+</span>
          </button>
          {pickerOpen ? <LayoutPinPicker variant="overlay" onClose={() => setPickerOpen(false)} /> : null}
        </span>
      ) : null}
      <span className="bottom-bar__layout-sep" aria-hidden="true" />
      <button
        type="button"
        className="bottom-bar__layout-close"
        aria-label="Close layout mode"
        onClick={() => {
          void bridge.closeLayout();
        }}
      >
        <span aria-hidden="true">×</span>
      </button>
    </div>
  );
}

/**
 * The bottom-bar Wi-Fi indicator (NIC-156). It reports what the machine actually
 * reports and nothing more: the radio's power state drives the glyph, and signal
 * strength dims the outer arcs. The four honest outcomes are visually distinct —
 * connected (accent arcs, dimmed by strength), on-but-unassociated (muted arcs),
 * off or absent (struck through), and no reading at all (struck through, and the
 * label says so rather than implying the radio is off).
 *
 * Read-only: the macOS menu bar owns turning Wi-Fi on and off (owner decision,
 * 2026-08-01) — this indicator reports state and is deliberately not a control.
 */
function WiFiIndicator({ network }: { network?: NetworkChannel }) {
  const power = network?.wifiPower;
  const linkMbps = network?.linkMbps;
  const signalLevel = signalLevelFromRssi(network?.signalRssi);
  const connected = power === "on" && (linkMbps !== undefined || network?.signalRssi !== undefined);

  let status: "on" | "idle" | "off" | "absent" | "unknown";
  let label: string;
  if (power === undefined) {
    status = "unknown";
    label = "Wi-Fi status unavailable";
  } else if (power === "absent") {
    status = "absent";
    label = "No Wi-Fi interface on this machine";
  } else if (power === "off") {
    status = "off";
    label = "Wi-Fi off";
  } else if (connected) {
    status = "on";
    label =
      linkMbps !== undefined
        ? `Wi-Fi connected · ${Math.round(linkMbps)} Mbps`
        : "Wi-Fi connected";
  } else {
    status = "idle";
    label = "Wi-Fi on · not connected";
  }

  const struck = status === "off" || status === "absent" || status === "unknown";

  return (
    <span
      className="bottom-bar__item bottom-bar__wifi"
      data-wifi={status}
      role="img"
      title={label}
      aria-label={label}
    >
      <HealthGlyph name={struck ? "network-off" : "network"} signalLevel={signalLevel} />
    </span>
  );
}

export function PersistentBottomBar({ now = new Date() }: { now?: Date } = {}) {
  const state = useDashboardState();
  const { openSettings } = useSettings();
  const { assistantName } = useAppearance();
  const { heimlich } = state;
  // Live weather (NIC-169, streamed via `weather.changed`) wins over the per-mode bootstrap
  // `weather`; absent until the native producer's first sample, so pre-Mac this is the mock value.
  const weather = state.liveWeather ?? state.weather;
  const battery = state.regions.systemHealth.battery;
  const barRef = useRef<HTMLElement>(null);

  // Report the bar's on-screen rect to the native shell (NIC-144): the window-snap
  // observer needs the bar's live geometry to keep other apps' windows above it. Post
  // on mount and whenever the bar's box or the viewport changes; `postShellControl`
  // no-ops in a plain browser, and ResizeObserver is feature-detected for jsdom.
  useEffect(() => {
    const el = barRef.current;
    if (!el) {
      return;
    }
    const report = (): void => {
      const rect = el.getBoundingClientRect();
      postShellControl("reportBottomBarRect", {
        rect: { x: rect.left, y: rect.top, width: rect.width, height: rect.height }
      });
    };
    report();
    window.addEventListener("resize", report);
    let observer: ResizeObserver | undefined;
    if (typeof ResizeObserver !== "undefined") {
      observer = new ResizeObserver(report);
      observer.observe(el);
    }
    return () => {
      window.removeEventListener("resize", report);
      observer?.disconnect();
    };
  }, []);

  const weatherLive =
    weather !== undefined && (weather.state === "ready" || weather.state === "stale");
  const batteryLive =
    (battery.state === "ready" || battery.state === "stale") && typeof battery.percent === "number";

  return (
    <footer className="bottom-bar shell-bottombar" aria-label="Status bar" ref={barRef}>
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

        {state.layoutSession ? (
          <>
            <Divider />
            <LayoutBar session={state.layoutSession} />
          </>
        ) : null}
      </div>

      <div className="bottom-bar__group bottom-bar__group--center">
        {/* Mode accent on the home dashboard only (design spec §5.12); themed via data-mode.
            Now an upward menu of all four modes (NIC-77). */}
        <BottomBarModeMenu />
      </div>

      <div className="bottom-bar__group bottom-bar__group--right">
        {/* Window management (NIC-143), shown only while layout mode is closed — the
            layout pill (left group) and this section never appear together. */}
        {state.layoutSession ? null : (
          <>
            <WindowManagementSection />
            <Divider />
          </>
        )}

        <WiFiIndicator network={state.regions.systemHealth.network} />

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
