import "../tokens/tokens.css";
import "../app.css";
import "../styles/responsive.css";
import "../shell/shell.css";
import "./companion.css";
import { HeimlichConsciousness } from "../shell/HeimlichConsciousness";
import { PersistentBottomBar } from "../shell/PersistentBottomBar";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { BridgeProvider } from "../state/BridgeProvider";
import { SettingsProvider } from "../state/SettingsProvider";
import { AppearanceProvider } from "../state/AppearanceProvider";
import { ThemeProvider } from "./ThemeProvider";
import { createDashboardRuntime } from "../state/bootstrapStore";

// The same runtime seam as AppRoot: the live WKWebView bridge inside the native
// shell (seeded from the injected bootstrap), the mock in a plain browser preview.
const runtime = createDashboardRuntime();
const bridge = runtime.bridge;
const store = runtime.store;

/**
 * The secondary-display companion surface (owner decision, 2026-07-06), loaded
 * by the native shell at `index.html?surface=companion` into each secondary
 * backdrop (NIC-120b).
 *
 * A deliberately reduced presence: the Heimlich consciousness stream filling the
 * display over the persistent bottom bar — no command bar, quick apps/actions,
 * agents, or conversation. Commands, conversations, and palette focus belong to
 * the main display; the companion mirrors shared state (mode theme, Heimlich
 * state, system health) from the same single `BridgeSession`, so it stays a
 * live presence, never a second control surface.
 */
export function CompanionApp() {
  return (
    <BridgeProvider bridge={bridge}>
      <DashboardStateProvider store={store}>
        <AppearanceProvider>
          <ThemeProvider>
            <SettingsProvider>
              <div className="companion-root" role="main" aria-label="CerebralHelm companion">
                <div className="companion-stage">
                  <HeimlichConsciousness />
                </div>
                <PersistentBottomBar />
              </div>
            </SettingsProvider>
          </ThemeProvider>
        </AppearanceProvider>
      </DashboardStateProvider>
    </BridgeProvider>
  );
}

export default CompanionApp;
