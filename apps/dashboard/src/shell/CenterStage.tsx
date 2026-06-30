import { QuickApps } from "./QuickApps";
import { QuickActions } from "./QuickActions";
import { useDashboardState } from "../state/DashboardStateProvider";
import { useActiveMode } from "./useActiveMode";
import { heimlichStateLabel } from "./labels";

/**
 * The calm, dominant center (constitution §6): the persistent Ask-Heimlich launcher, Quick
 * Apps, and the Heimlich consciousness surface that always owns the center (course-correction
 * A.1) — mode-aware greeting + status text + the 4 + 4 quick-action geometry. This is the
 * `#main` skip-link target; the main product is immediately visible (NIC-53).
 */
export function CenterStage() {
  const { heimlich } = useDashboardState();
  const { greeting } = useActiveMode();

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

      <QuickApps />

      <section className="heimlich" aria-label="Heimlich">
        <div className="heimlich__ambient">
          <p className="eyebrow">Heimlich · {heimlichStateLabel(heimlich.state)}</p>
          {greeting ? <p className="heimlich__greeting">{greeting.fallback}</p> : null}
        </div>
        <QuickActions />
      </section>
    </main>
  );
}
