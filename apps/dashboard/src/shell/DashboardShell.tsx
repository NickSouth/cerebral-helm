import { LeftRail } from "./LeftRail";
import { CenterStage } from "./CenterStage";
import { RightRail } from "./RightRail";
import { PersistentBottomBar } from "./PersistentBottomBar";

/**
 * The shared three-zone shell (design spec §10 composition, constitution §6): one layout
 * grammar for every mode — left information rail, calm dominant Heimlich center, right
 * operational rail, and a persistent bottom bar on its own track. Switching mode re-themes
 * via `data-mode` without remounting this shell.
 */
export function DashboardShell() {
  return (
    <div className="dashboard-shell">
      <LeftRail />
      <CenterStage />
      <RightRail />
      <PersistentBottomBar />
    </div>
  );
}

export default DashboardShell;
