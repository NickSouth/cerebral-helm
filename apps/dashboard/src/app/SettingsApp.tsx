import "../tokens/tokens.css";
import "../app.css";
import "../styles/responsive.css";
import "../shell/shell.css";
import "../shell/settings/settings.css";
import { SettingsSurface } from "../shell/settings/SettingsOverlay";
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
 * The dedicated settings window's React entry (backdrop-policy decision,
 * 2026-07-06), loaded by the native shell at `index.html?surface=settings` into
 * its own normal-level `NSWindow` — the dashboard is a strict backdrop, so
 * settings must be a real window that can sit above other apps (reverses the
 * NIC-76 overlay-only decision).
 *
 * Renders the same two-pane `SettingsSurface` as the browser overlay, standalone
 * and edge-to-edge; the provider stack matches AppRoot so panels read modes,
 * capabilities, and theme identically. Closing posts `shellControl.closeSettings`
 * — the native window owns its own lifecycle.
 */
export function SettingsApp() {
  return (
    <BridgeProvider bridge={bridge}>
      <DashboardStateProvider store={store}>
        <AppearanceProvider>
          <ThemeProvider>
            <SettingsProvider surface="standalone">
              <div
                className="settings-window"
                data-standalone="true"
                role="main"
                aria-label="Settings"
              >
                <SettingsSurface />
              </div>
            </SettingsProvider>
          </ThemeProvider>
        </AppearanceProvider>
      </DashboardStateProvider>
    </BridgeProvider>
  );
}

export default SettingsApp;
