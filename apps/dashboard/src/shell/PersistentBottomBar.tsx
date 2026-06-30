import { useDashboardState } from "../state/DashboardStateProvider";
import { heimlichStateLabel } from "./labels";

/**
 * The thin, persistent bottom bar on its own layout track (constitution §6). C1 reserves
 * the track with a minimal honest placeholder; the full bar (metrics, time, emergency
 * controls, mode-accent-on-home) is NIC-59. Metrics render unavailable pre-Mac.
 */
export function PersistentBottomBar() {
  const { mode, heimlich } = useDashboardState();

  return (
    <footer className="bottom-bar" aria-label="Status bar">
      <span className="bottom-bar__item">Heimlich · {heimlichStateLabel(heimlich.state)}</span>
      <span className="bottom-bar__item">{mode}</span>
      <span className="bottom-bar__item bottom-bar__metrics">
        <span className="unavailable">Metrics — not implemented</span>
      </span>
      <span className="bottom-bar__item bottom-bar__settings">Settings</span>
    </footer>
  );
}
