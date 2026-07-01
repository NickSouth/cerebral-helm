import { LeftRail } from "./LeftRail";
import { CenterStage } from "./CenterStage";
import { RightRail } from "./RightRail";
import { PersistentBottomBar } from "./PersistentBottomBar";
import { ConfirmationOverlay } from "./ConfirmationOverlay";
import { CommandSurface } from "./CommandSurface";
import { useConversation } from "../state/ConversationProvider";

/**
 * The shared three-zone shell (design spec §10 composition, constitution §6): one layout
 * grammar for every mode — a top-row global Ask-Heimlich launcher over the center, a left
 * information rail, the calm dominant Heimlich center, a right operational rail, and a
 * persistent bottom bar on its own track. The launcher (C0) lives on its own header row so
 * the rails begin at the Quick Apps line and run to the bottom (visual reference, Plate 01).
 * Switching mode re-themes via `data-mode` without remounting this shell. The overlay host
 * (design spec §10) carries the system surfaces that composite over the shell.
 */
export function DashboardShell() {
  const conversation = useConversation();

  return (
    <div className="dashboard-shell">
      <div className="shell-search">
        <CommandSurface
          variant="launcher"
          placeholder="Ask Heimlich or type a command…"
          ariaLabel="Ask Heimlich or type a command"
          onSubmit={conversation.submit}
        />
      </div>
      <LeftRail />
      <CenterStage />
      <RightRail />
      <PersistentBottomBar />
      <ConfirmationOverlay />
    </div>
  );
}

export default DashboardShell;
