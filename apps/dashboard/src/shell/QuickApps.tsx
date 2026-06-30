import { Panel } from "./Panel";
import { AppGlyph } from "./AppGlyph";
import { useActiveMode } from "./useActiveMode";
import { appDefinition } from "../appCatalog/appCatalog";

/**
 * C1 Quick Apps (design spec §5.6): the active mode's configured app shortcuts plus a final
 * "More Apps" control. Apps render with placeholder category glyphs (real OS icons on Mac).
 * Launching is a Mac-only capability, so the shortcuts are honest-disabled pre-Mac.
 */
export function QuickApps() {
  const { quickApps } = useActiveMode();

  return (
    <Panel label="Quick Apps" labelId="region-quick-apps">
      <ul className="quick-apps">
        {quickApps.map((id) => {
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
        <li>
          <button type="button" className="quick-app quick-app--more" disabled aria-disabled="true" title="App discovery is available on the macOS host">
            <span className="quick-app__icon" aria-hidden="true">+</span>
            <span className="quick-app__label">More Apps</span>
          </button>
        </li>
      </ul>
    </Panel>
  );
}
