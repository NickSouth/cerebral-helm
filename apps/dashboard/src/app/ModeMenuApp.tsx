import "../tokens/tokens.css";
import "../app.css";
import "../styles/responsive.css";
import "../shell/shell.css";
import { ModeMenuSurface } from "../shell/ModeMenuSurface";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { BridgeProvider } from "../state/BridgeProvider";
import { AppearanceProvider } from "../state/AppearanceProvider";
import { ThemeProvider } from "./ThemeProvider";
import { useTransparentSurface } from "./useTransparentSurface";
import { createDashboardRuntime } from "../state/bootstrapStore";

// The same runtime seam as AppRoot: the live WKWebView bridge inside the native shell
// (seeded from the injected bootstrap), the mock in a plain browser preview.
const runtime = createDashboardRuntime();
const bridge = runtime.bridge;
const store = runtime.store;

/**
 * The mode-swap dropdown's React entry (NIC-144), loaded by the native shell at
 * `index.html?surface=modemenu` into its own transparent, top-most window positioned
 * above the bottom bar's mode control. The dashboard is a strict backdrop, so the
 * dropdown must be a real window to sit above open apps — the same reasoning as the
 * command palette and More Apps launcher.
 *
 * The window is transparent (no chrome, no opaque background) so only the menu paints;
 * ThemeProvider still themes it to the active mode. The host document — and
 * ThemeProvider's own `.app-root`, which normally carries the opaque per-mode
 * background — are forced transparent here, since this surface (unlike the dashboard)
 * must show the desktop through everything but the menu itself.
 */
export function ModeMenuApp() {
  useTransparentSurface();

  return (
    <BridgeProvider bridge={bridge}>
      <DashboardStateProvider store={store}>
        <AppearanceProvider>
          <ThemeProvider>
            <ModeMenuSurface />
          </ThemeProvider>
        </AppearanceProvider>
      </DashboardStateProvider>
    </BridgeProvider>
  );
}

export default ModeMenuApp;
