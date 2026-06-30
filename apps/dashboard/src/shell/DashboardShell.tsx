import { LeftRail } from "./LeftRail";
import { CenterStage } from "./CenterStage";
import { RightRail } from "./RightRail";
import { PersistentBottomBar } from "./PersistentBottomBar";
import { ConfirmationOverlay } from "./ConfirmationOverlay";

/**
 * The shared three-zone shell (design spec §10 composition, constitution §6): one layout
 * grammar for every mode — left information rail, calm dominant Heimlich center, right
 * operational rail, and a persistent bottom bar on its own track. Switching mode re-themes
 * via `data-mode` without remounting this shell. The overlay host (design spec §10) carries
 * the system surfaces that composite over the shell; the confirmation window is the first.
 */
export function DashboardShell() {
  return (
    <div className="dashboard-shell">
      <LeftRail />
      <CenterStage />
      <RightRail />
      <PersistentBottomBar />
      <ConfirmationOverlay />
    </div>
  );
}

export default DashboardShell;
