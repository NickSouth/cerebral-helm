import { Panel } from "./Panel";
import { Unavailable } from "../components/Unavailable";
import { useDashboardState } from "../state/DashboardStateProvider";
import { heimlichStateLabel } from "./labels";

/** The binding 4 + 4 quick-action geometry (§5.7): four bars over four boxes, always 8 slots. */
function QuickActionGrid() {
  const bars = [0, 1, 2, 3];
  const boxes = [0, 1, 2, 3];
  return (
    <div className="quick-actions" role="group" aria-label="Quick actions">
      <div className="quick-actions__bars">
        {bars.map((index) => (
          <button key={`bar-${index}`} type="button" className="quick-action quick-action--bar" disabled aria-disabled="true">
            Coming soon
          </button>
        ))}
      </div>
      <div className="quick-actions__boxes">
        {boxes.map((index) => (
          <button key={`box-${index}`} type="button" className="quick-action quick-action--box" disabled aria-disabled="true">
            Coming soon
          </button>
        ))}
      </div>
    </div>
  );
}

/**
 * The calm, dominant center (constitution §6): the persistent Ask-Heimlich launcher, Quick
 * Apps, and the Heimlich consciousness surface that always owns the center (course-correction
 * A.1) with the 4 + 4 quick-action geometry. This is the `#main` skip-link target — the main
 * product is immediately visible (NIC-53).
 */
export function CenterStage() {
  const { heimlich } = useDashboardState();

  return (
    <main id="main" tabIndex={-1} className="shell-center">
      <div className="global-search">
        <input
          className="global-search__input"
          type="text"
          placeholder="Ask Heimlich or type a command…"
          aria-label="Ask Heimlich or type a command"
          disabled
        />
      </div>

      <Panel label="Quick Apps" labelId="region-quick-apps">
        <Unavailable />
      </Panel>

      <section className="heimlich" aria-label="Heimlich">
        <div className="heimlich__ambient">
          <p className="eyebrow">Heimlich</p>
          <p className="heimlich__state">{heimlichStateLabel(heimlich.state)}</p>
        </div>
        <QuickActionGrid />
      </section>
    </main>
  );
}
