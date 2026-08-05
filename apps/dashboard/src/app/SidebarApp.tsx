import { useCallback, useEffect, useState, type ReactNode } from "react";
import "../tokens/tokens.css";
import "../app.css";
import "../styles/responsive.css";
import "../shell/shell.css";
import "./sidebar.css";
import { HeimlichAvatar } from "../shell/HeimlichAvatar";
import { HeimlichConsciousness } from "../shell/HeimlichConsciousness";
import { CommandSurface } from "../shell/CommandSurface";
import { ActionStatusIndicator } from "../shell/ActionStatusIndicator";
import { ModeSwitcher } from "../shell/ModeSwitcher";
import { AgentRoster } from "../shell/AgentRoster";
import { QuickActions } from "../shell/QuickActions";
import { QuickApps } from "../shell/QuickApps";
import { SchedulePanel } from "../shell/SchedulePanel";
import { Panel } from "../shell/Panel";
import { PanelGlyph } from "../shell/PanelGlyph";
import { DashboardStateProvider, useDashboardState } from "../state/DashboardStateProvider";
import { BridgeProvider, useBridge } from "../state/BridgeProvider";
import { ActionStatusProvider, useActionStatus } from "../state/ActionStatusProvider";
import { SettingsProvider } from "../state/SettingsProvider";
import { AppearanceProvider, useAppearance } from "../state/AppearanceProvider";
import { ReportProvider } from "../state/ReportProvider";
import { InputProvider } from "../state/InputProvider";
import { useUiPosture } from "../state/useUiPosture";
import { ThemeProvider } from "./ThemeProvider";
import { createDashboardRuntime } from "../state/bootstrapStore";
import { withModeWave } from "../shell/modeWave";
import { postSidebarControl } from "./sidebarControl";

// The same runtime seam as AppRoot: the live WKWebView bridge inside the native shell (seeded
// from the injected bootstrap), the mock in a plain browser preview. Mode switches commit inside
// the wave, exactly as on the dashboard, so switching from the sidebar re-themes identically.
const runtime = createDashboardRuntime();
const bridge = runtime.bridge;
const store = withModeWave(runtime.store);

/** The focus hook the native shell installs on, called on every summon. */
interface SidebarFocusWindow extends Window {
  __cerebralFocusSidebar?: () => void;
  __cerebralBlurSidebar?: () => void;
}

/** Chevron pointing back at the screen edge — the "tuck me away" affordance. */
function CollapseGlyph() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false">
      <path d="M15 6 L9 12 L15 18" />
    </svg>
  );
}

/** A pushpin — upright while pinned, tilted while not (the sidebar auto-hides unless pinned). */
function PinGlyph({ pinned }: { pinned: boolean }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false" style={pinned ? undefined : { transform: "rotate(35deg)" }}>
      <path d="M12 17v5" />
      <path d="M9 3h6l-1 6 3 3v2H7v-2l3-3z" />
    </svg>
  );
}

/** A grid of panes — "put the dashboard back in front of me". */
function DashboardGlyph() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false">
      <rect x="3" y="3" width="18" height="18" rx="2" />
      <path d="M3 9h18M9 21V9" />
    </svg>
  );
}

/**
 * The edge sidebar's content: the dashboard's own controls re-laid as a single narrow column,
 * for reaching Heimlich without leaving a fullscreen app.
 *
 * Every control here is the *same component* the dashboard renders — command bar, mode switcher,
 * quick actions, Today, quick apps, agents — bound to the same `BridgeSession`. Nothing is forked
 * or re-implemented, so a mode switched here is the mode everywhere, and a quick action run here
 * is the same run with the same confirmation policy.
 *
 * Report and Input quick actions (daily brief, capture note, create event…) are deliberately NOT
 * rendered here — see `SidebarHandoff`, which reveals the dashboard and opens them in their normal
 * place instead.
 */
function SidebarSurface() {
  const bridgeApi = useBridge();
  const { announce } = useActionStatus();
  const { assistantName } = useAppearance();
  const { mode, modes, windowCollapse } = useDashboardState();
  const posture = useUiPosture();
  const [pinned, setPinned] = useState(false);

  // Resolve the id by lookup, not by lowercasing the label (the bottom bar's approach): a mode
  // whose display label diverges from its config id would otherwise throw here.
  const modeId = modes.find((modeView) => modeView.label === mode)?.id;
  const collapsed = modeId ? (windowCollapse?.[modeId] ?? false) : false;

  // Identical to the dashboard's launcher wiring (DashboardShell): an accepted command surfaces
  // its result through the event stream and the status line; a rejected one has no wired
  // capability yet, so we report the honest MVP state.
  const runCommand = useCallback(
    (text: string) => {
      const trimmed = text.trim();
      if (!trimmed) {
        return;
      }
      void bridgeApi
        .submitCommand({ rawInput: trimmed, source: "dashboard" })
        .then((receipt) => {
          if (!receipt.accepted) {
            announce("Heimlich not implemented");
          }
        })
        .catch(() => {
          announce("The command could not be sent.", "error");
        });
    },
    [bridgeApi, announce]
  );

  const fetchSuggestions = useCallback(
    (query: string) => bridgeApi.suggestCommands({ query }).then((result) => result.suggestions),
    [bridgeApi]
  );

  // Escape tucks the sidebar back to the edge (palette convention).
  useEffect(() => {
    function onKeyDown(event: KeyboardEvent): void {
      if (event.key === "Escape") {
        postSidebarControl("dismiss");
      }
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  // The native shell calls this on every summon so the pre-warmed (previously hidden) webview
  // focuses its command input immediately — the global hotkey opens the sidebar ready to type
  // (owner decision, 2026-08-03: the hotkey targets this, not the palette).
  //
  // Blur first: after a dismiss the input is often still `document.activeElement`, making a bare
  // `.focus()` a no-op that fires no focus event, leaving React's `focused` state stale so the
  // suggestion list never returns. The palette needed this same fix (NIC-77).
  //
  // The blur counterpart is what a hover reveal calls. The webview is pre-warmed and keeps
  // whatever focus it had when last dismissed, so without an explicit blur the command box would
  // still be active — and its suggestion list open — the moment the column slides out.
  useEffect(() => {
    const target = window as SidebarFocusWindow;
    const input = () => document.querySelector<HTMLInputElement>(".sidebar-search input");
    target.__cerebralFocusSidebar = () => {
      const el = input();
      el?.blur();
      el?.focus();
      el?.select();
    };
    target.__cerebralBlurSidebar = () => {
      input()?.blur();
    };
    return () => {
      delete target.__cerebralFocusSidebar;
      delete target.__cerebralBlurSidebar;
    };
  }, []);

  // A pinned sidebar must not auto-hide when the pointer leaves the edge, which is native
  // behavior — so the pin state is pushed across the control channel rather than kept here.
  const togglePin = useCallback(() => {
    setPinned((current) => {
      const next = !current;
      postSidebarControl(next ? "pin" : "unpin");
      return next;
    });
  }, []);

  // "Return to dashboard" reuses the existing collapse-all bucket (NIC-143): the dashboard is a
  // backdrop that never lifts, so revealing it means stowing the windows covering it.
  const returnToDashboard = useCallback(() => {
    if (!modeId || posture.readOnly) {
      return;
    }
    void bridgeApi.toggleModeCollapse({ modeId });
    postSidebarControl("dismiss");
  }, [bridgeApi, modeId, posture.readOnly]);

  return (
    <div className="sidebar-root" role="complementary" aria-label={`${assistantName} sidebar`}>
      <header className="sidebar-head">
        <span className="sidebar-head__portrait" aria-hidden="true">
          <HeimlichAvatar />
        </span>
        <span className="sidebar-head__identity">
          <span className="sidebar-head__name">{assistantName}</span>
          <span className="sidebar-head__mode">
            <span className="sidebar-head__dot" aria-hidden="true" />
            {mode} Mode active
          </span>
        </span>
        <button
          type="button"
          className="sidebar-head__control"
          aria-label={pinned ? "Unpin the sidebar" : "Keep the sidebar open"}
          aria-pressed={pinned}
          title={pinned ? "Unpin — hide when the pointer leaves" : "Pin — keep open"}
          onClick={togglePin}
        >
          <PinGlyph pinned={pinned} />
        </button>
        <button
          type="button"
          className="sidebar-head__control"
          aria-label="Hide the sidebar"
          title="Hide (Esc)"
          onClick={() => postSidebarControl("dismiss")}
        >
          <CollapseGlyph />
        </button>
      </header>

      {/* The single execution-feedback surface, same as the dashboard's top-left cell (NIC-124). */}
      <ActionStatusIndicator />

      <div className="sidebar-stream" aria-hidden="true">
        <HeimlichConsciousness />
      </div>

      <div className="sidebar-search">
        <CommandSurface
          variant="launcher"
          placeholder={`Ask ${assistantName} or run a command…`}
          ariaLabel="Type a command"
          onSubmit={runCommand}
          fetchSuggestions={fetchSuggestions}
          disabled={posture.readOnly}
        />
      </div>

      <ModeSwitcher />

      <div className="sidebar-scroll">
        <QuickActions />
        <SchedulePanel />
        <QuickApps />
        <Panel label="Agents" labelId="sidebar-agents" icon={<PanelGlyph name="agents" />}>
          <AgentRoster />
        </Panel>
      </div>

      <footer className="sidebar-foot">
        <button
          type="button"
          className="sidebar-foot__action"
          onClick={returnToDashboard}
          disabled={posture.readOnly}
          title={
            collapsed
              ? "Bring the stowed windows back"
              : "Stow the open windows so the dashboard behind them is visible"
          }
        >
          <DashboardGlyph />
          {collapsed ? "Restore windows" : "Return to dashboard"}
        </button>
        <button
          type="button"
          className="sidebar-foot__action sidebar-foot__action--quiet"
          onClick={() => postSidebarControl("dismiss")}
        >
          <CollapseGlyph />
          Collapse sidebar
        </button>
      </footer>
    </div>
  );
}

/**
 * Sends Report and Input quick actions to the dashboard instead of opening them in the column
 * (owner decision, 2026-08-03).
 *
 * A report is a reading surface and a form wants room; both are designed for the centre panel, and
 * rendering a second copy inside 340px read as a window-inside-a-window. So opening one from the
 * sidebar does what the user would have done by hand: stow the windows covering the backdrop —
 * the same collapse bucket "Return to dashboard" uses — and open the surface in its normal place.
 *
 * Lives inside the state providers (it needs the bridge and the active mode) and outside the
 * Report/Input providers, which it configures.
 */
function SidebarHandoff({ children }: { children: ReactNode }) {
  const bridge = useBridge();
  const { mode, modes, windowCollapse } = useDashboardState();
  const modeId = modes.find((modeView) => modeView.label === mode)?.id;
  const collapsed = modeId ? (windowCollapse?.[modeId] ?? false) : false;

  const reveal = useCallback(
    (kind: "report" | "input", id: string) => {
      // Only collapse when something is actually covering the dashboard — toggling an
      // already-collapsed bucket would *restore* every window and bury it again.
      if (modeId && !collapsed) {
        void bridge.toggleModeCollapse({ modeId });
      }
      // The native side dismisses the sidebar and opens the surface on the dashboard webview.
      postSidebarControl("revealDashboard", { [kind]: id });
      return true;
    },
    [bridge, modeId, collapsed]
  );

  const onReport = useCallback((id: string) => reveal("report", id), [reveal]);
  const onInput = useCallback((id: string) => reveal("input", id), [reveal]);

  return (
    <ReportProvider handoff={onReport}>
      <InputProvider handoff={onInput}>{children}</InputProvider>
    </ReportProvider>
  );
}

/**
 * The edge sidebar's React entry, loaded by the native shell at `index.html?surface=sidebar` into
 * the left-edge panel that reveals on a hover-dwell at the screen edge (owner decision, 2026-08-03).
 *
 * It floats over other apps rather than living in the backdrop, which is the sanctioned pattern for
 * a must-be-seen surface (backdrop-window policy, 2026-07-06): the dashboard itself never lifts.
 */
export function SidebarApp() {
  return (
    <BridgeProvider bridge={bridge}>
      <DashboardStateProvider store={store}>
        <AppearanceProvider>
          <ThemeProvider>
            <ActionStatusProvider>
              <SettingsProvider>
                <SidebarHandoff>
                  <SidebarSurface />
                </SidebarHandoff>
              </SettingsProvider>
            </ActionStatusProvider>
          </ThemeProvider>
        </AppearanceProvider>
      </DashboardStateProvider>
    </BridgeProvider>
  );
}

export default SidebarApp;
