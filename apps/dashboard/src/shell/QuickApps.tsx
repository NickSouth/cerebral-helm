import { Panel } from "./Panel";
import { AppGlyph } from "./AppGlyph";
import { useActiveMode } from "./useActiveMode";
import { appDefinition } from "../appCatalog/appCatalog";

/** The five app slots + a sixth "More Apps" control (design spec §5.6: one-to-five apps + More). */
const APP_SLOTS = 5;

/** A pin silhouette shown in empty app slots — an addable placeholder (pinning is a Mac capability). */
function PinGlyph() {
  return (
    <svg
      className="app-glyph"
      viewBox="0 0 24 24"
      width="22"
      height="22"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <path d="M9 3.5h6l-1 5 3 3v1.5H7V11.5l3-3-1-5z" />
      <path d="M12 14v6.5" />
    </svg>
  );
}

/** A 3×3 grid of tiles — the app-drawer glyph for the "More Apps" menu. */
function AppsGridGlyph() {
  const coords = [4, 9.75, 15.5];
  return (
    <svg
      className="app-glyph"
      viewBox="0 0 24 24"
      width="22"
      height="22"
      fill="currentColor"
      aria-hidden="true"
      focusable="false"
    >
      {coords.flatMap((y) => coords.map((x) => <rect key={`${x}-${y}`} x={x} y={y} width="4.5" height="4.5" rx="1.2" />))}
    </svg>
  );
}

/**
 * C1 Quick Apps (design spec §5.6): the active mode's configured app shortcuts, padded to five
 * fixed slots (empty slots show a "Pin app" placeholder), plus a final "More Apps" control — six
 * boxes spanning the panel edge-to-edge. Each slot mirrors the mode toggle: icon over label.
 * Apps render with placeholder category glyphs (real OS icons on Mac). Launching, pinning, and
 * app discovery are Mac-only capabilities, so every control is honest-disabled pre-Mac.
 */
export function QuickApps() {
  const { quickApps } = useActiveMode();
  const apps = quickApps.slice(0, APP_SLOTS);
  const emptySlots = Math.max(0, APP_SLOTS - apps.length);

  return (
    <Panel label="Quick Apps" labelId="region-quick-apps">
      <ul className="quick-apps">
        {apps.map((id) => {
          const app = appDefinition(id);
          return (
            <li key={id}>
              <button type="button" className="quick-app" disabled aria-disabled="true" title="Launching apps is available on the macOS host">
                <span className="quick-app__icon">
                  <AppGlyph category={app?.category ?? "files"} />
                </span>
                <span className="quick-app__label">{app?.label ?? id}</span>
              </button>
            </li>
          );
        })}
        {Array.from({ length: emptySlots }, (_, index) => (
          <li key={`pin-${index}`}>
            <button
              type="button"
              className="quick-app quick-app--pin"
              disabled
              aria-disabled="true"
              title="Pin an app to this slot (available on the macOS host)"
            >
              <span className="quick-app__icon" aria-hidden="true">
                <PinGlyph />
              </span>
              <span className="quick-app__label">Pin app</span>
            </button>
          </li>
        ))}
        <li>
          <button type="button" className="quick-app quick-app--more" disabled aria-disabled="true" title="App discovery is available on the macOS host">
            <span className="quick-app__icon" aria-hidden="true">
              <AppsGridGlyph />
            </span>
            <span className="quick-app__label">More Apps</span>
          </button>
        </li>
      </ul>
    </Panel>
  );
}
