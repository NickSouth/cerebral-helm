import { Panel } from "./Panel";
import { Unavailable } from "../components/Unavailable";

/**
 * The left information rail (constitution §6 / design spec §5.3): L1 Today, L2 System
 * Health, L3 free widget, L4 News. C1 ships the labelled region containers; their data
 * binding is NIC-54. Unwired bodies render honest-unavailable (constitution §2.5).
 */
export function LeftRail() {
  return (
    <aside className="shell-rail shell-left" aria-label="Information">
      <Panel label="Today" labelId="region-today">
        <Unavailable />
      </Panel>
      <Panel label="System Health" labelId="region-health">
        <Unavailable />
      </Panel>
      <Panel label="Widget" labelId="region-widget-left">
        <Unavailable />
      </Panel>
      <Panel label="News" labelId="region-news">
        <Unavailable />
      </Panel>
    </aside>
  );
}
