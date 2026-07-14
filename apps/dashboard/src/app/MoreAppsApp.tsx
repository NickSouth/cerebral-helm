import "../tokens/tokens.css";
import "../app.css";
import "../styles/responsive.css";
import "../shell/shell.css";
import { MoreAppsPicker } from "../shell/MoreAppsPicker";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { BridgeProvider } from "../state/BridgeProvider";
import { AppearanceProvider } from "../state/AppearanceProvider";
import { ThemeProvider } from "./ThemeProvider";
import { postShellControl } from "../shell/shellControl";
import { createDashboardRuntime } from "../state/bootstrapStore";

// The same runtime seam as AppRoot: the live WKWebView bridge inside the native
// shell (seeded from the injected bootstrap), the mock in a plain browser preview.
const runtime = createDashboardRuntime();
const bridge = runtime.bridge;
const store = runtime.store;

/**
 * The More Apps launcher window's React entry (NIC-148), loaded by the native
 * shell at `index.html?surface=moreapps` into its own top-most borderless
 * `NSWindow`. The dashboard is a strict backdrop, so the launcher must be a real
 * window that can sit above other apps — the same reasoning as the settings window
 * (backdrop-policy decision, 2026-07-06).
 *
 * Renders the launch-only {@link MoreAppsPicker} filling the window (its themed bar
 * and × replace native chrome). Every close path — the ×, Escape, or an accepted
 * app launch — posts `shellControl.closeMoreApps`, so opening an app dismisses the
 * window and the native shell owns the window's lifecycle.
 */
export function MoreAppsApp() {
  return (
    <BridgeProvider bridge={bridge}>
      <DashboardStateProvider store={store}>
        <AppearanceProvider>
          <ThemeProvider>
            <div className="apps-window" role="main" aria-label="All applications">
              <MoreAppsPicker variant="standalone" onClose={() => postShellControl("closeMoreApps")} />
            </div>
          </ThemeProvider>
        </AppearanceProvider>
      </DashboardStateProvider>
    </BridgeProvider>
  );
}

export default MoreAppsApp;
