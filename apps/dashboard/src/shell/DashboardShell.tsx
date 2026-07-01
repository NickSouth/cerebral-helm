import { LeftRail } from "./LeftRail";
import { CenterStage } from "./CenterStage";
import { RightRail } from "./RightRail";
import { PersistentBottomBar } from "./PersistentBottomBar";
import { ConfirmationOverlay } from "./ConfirmationOverlay";
import { CommandSurface } from "./CommandSurface";
import { SystemStatusBanner } from "./SystemStatusBanner";
import { DashboardSkeleton } from "./DashboardSkeleton";
import { useConversation } from "../state/ConversationProvider";
import { useUiPosture } from "../state/useUiPosture";
import { useAmbientBeam } from "./useAmbientBeam";
import { useRef } from "react";

/**
 * The shared three-zone shell (design spec §10 composition, constitution §6): one layout
 * grammar for every mode — a top-row global Ask-Heimlich launcher over the center, a left
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
  const conversation = useConversation();
  const posture = useUiPosture();
  const shellRef = useRef<HTMLDivElement>(null);
  useAmbientBeam(shellRef);

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
          <div className="shell-search">
            <CommandSurface
              variant="launcher"
              placeholder="Ask Heimlich or type a command…"
              ariaLabel="Ask Heimlich or type a command"
              onSubmit={conversation.submit}
              disabled={posture.readOnly}
            />
          </div>
          <LeftRail />
          <CenterStage />
          <RightRail />
        </div>
      )}
      <PersistentBottomBar />
      <ConfirmationOverlay />
    </div>
  );
}

export default DashboardShell;
