import { LeftRail } from "./LeftRail";
import { CenterStage } from "./CenterStage";
import { RightRail } from "./RightRail";
import { PersistentBottomBar } from "./PersistentBottomBar";
import { ConfirmationOverlay } from "./ConfirmationOverlay";
import { SettingsOverlay } from "./settings/SettingsOverlay";
import { CommandSurface } from "./CommandSurface";
import { ActionStatusIndicator } from "./ActionStatusIndicator";
import { SystemStatusBanner } from "./SystemStatusBanner";
import { BrandMark, BrandWordmark } from "./BrandMark";
import { DashboardSkeleton } from "./DashboardSkeleton";
import { useBridge } from "../state/BridgeProvider";
import { useReports } from "../state/ReportProvider";
import { useInputs } from "../state/InputProvider";
import { useActionStatus } from "../state/ActionStatusProvider";
import { useSettings } from "../state/SettingsProvider";
import { useUiPosture } from "../state/useUiPosture";
import { useAmbientBeam } from "./useAmbientBeam";
import { useCallback, useEffect, useRef } from "react";

/** The native shell's intent channel into the dashboard (NIC-76 window-role choreography). */
interface ShellIntentWindow extends Window {
  __cerebralShell?: {
    submitCommand?: (text: string) => void;
    openSettings?: () => void;
    /** Open a Report / Input here rather than in the surface that asked. The edge sidebar uses
     *  these: its column is too narrow to read a brief or fill in a form, so it reveals the
     *  dashboard and hands the surface over (owner decision, 2026-08-03). */
    openReport?: (reportId: string) => void;
    openInput?: (actionId: string) => void;
  };
}

/**
 * The shared three-zone shell (design spec §10 composition, constitution §6): one layout
 * grammar for every mode — a top-row global command launcher over the center, a left
 * information rail, the calm dominant Heimlich center, a right operational rail, and a
 * persistent bottom bar on its own track. The launcher (C0) lives on its own header row so
 * the rails begin at the Quick Apps line and run to the bottom (visual reference, Plate 01).
 * Switching mode re-themes via `data-mode` without remounting this shell. The overlay host
 * (design spec §10) carries the system surfaces that composite over the shell.
 *
 * Width invariants: the column grid (`dashboard-canvas`) caps at a max width and centers on very
 * wide screens, while the persistent bottom bar is a full-width sibling that always spans the
 * whole screen. Height invariant: the whole thing scales with viewport height (see the rem token
 * layer + the viewport-height root font-size).
 */
export function DashboardShell() {
  const bridge = useBridge();
  const { announce } = useActionStatus();
  const settings = useSettings();
  const reports = useReports();
  const inputs = useInputs();
  const posture = useUiPosture();
  const shellRef = useRef<HTMLDivElement>(null);
  useAmbientBeam(shellRef);

  // Dispatch a raw command through the shared bridge (FR-CMD-01), from the top launcher or the
  // native shell-intent hook. An accepted command surfaces its result through the event stream /
  // the top-left status line. A rejected command has no wired capability yet (the Heimlich chat
  // was removed — NIC-124), so we report the honest MVP state rather than opening a conversation.
  const runCommand = useCallback(
    (text: string) => {
      const trimmed = text.trim();
      if (!trimmed) {
        return;
      }
      void bridge
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
    [bridge, announce]
  );

  // Ranked, capability-aware suggestions for the launcher (NIC-168): the bridge engine
  // resolves typos and inexact input over the live catalogs; a failure inside the surface
  // degrades to the bare input, so the command locus never depends on this call.
  const fetchSuggestions = useCallback(
    (query: string) => bridge.suggestCommands({ query }).then((result) => result.suggestions),
    [bridge]
  );

  // Register the native shell's intent hook so the menu bar / command palette can drive the
  // dashboard: a command submission dispatches through the bridge, and "Settings…" opens the
  // web settings overlay (NIC-76). Registered once; it calls the latest handlers via refs so
  // the callbacks never go stale.
  const runCommandRef = useRef(runCommand);
  runCommandRef.current = runCommand;
  const openSettingsRef = useRef(settings.openSettings);
  openSettingsRef.current = settings.openSettings;
  const openReportRef = useRef(reports.openReport);
  openReportRef.current = reports.openReport;
  const openInputRef = useRef(inputs.openInput);
  openInputRef.current = inputs.openInput;
  useEffect(() => {
    const shellWindow = window as ShellIntentWindow;
    shellWindow.__cerebralShell = {
      submitCommand: (text: string) => runCommandRef.current(text),
      openSettings: () => openSettingsRef.current(),
      openReport: (reportId: string) => openReportRef.current(reportId),
      openInput: (actionId: string) => openInputRef.current(actionId)
    };
    return () => {
      delete shellWindow.__cerebralShell;
    };
  }, []);

  return (
    <div className="dashboard-shell" ref={shellRef} data-read-only={posture.readOnly || undefined}>
      {/* Full-width degraded ribbon (sibling of the capped canvas), never replacing the shell. */}
      <SystemStatusBanner />
      {posture.loading ? (
        <div className="dashboard-canvas dashboard-canvas--loading">
          <DashboardSkeleton />
        </div>
      ) : (
        <div className="dashboard-canvas">
          {/* Top-left header cell: the single execution-feedback surface (NIC-124). */}
          <ActionStatusIndicator />
          <div className="shell-search">
            <CommandSurface
              variant="launcher"
              placeholder="Type a command…"
              ariaLabel="Type a command"
              onSubmit={runCommand}
              fetchSuggestions={fetchSuggestions}
              disabled={posture.readOnly}
            />
          </div>
          {/* Product brand pinned to the top-right corner of the header row: wordmark, then the
              helm mark in the corner itself. Re-tints with the mode via the accent tokens. */}
          <div className="shell-brand" role="img" aria-label="CerebralHelm">
            <BrandWordmark />
            <BrandMark />
          </div>
          <LeftRail />
          <CenterStage />
          <RightRail />
        </div>
      )}
      <PersistentBottomBar />
      <ConfirmationOverlay />
      <SettingsOverlay />
    </div>
  );
}

export default DashboardShell;
