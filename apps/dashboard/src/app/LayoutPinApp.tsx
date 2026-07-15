import "../tokens/tokens.css";
import "../app.css";
import "../styles/responsive.css";
import "../shell/shell.css";
import { LayoutPinPicker } from "../shell/LayoutPinPicker";
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
 * The layout hotswap "+" window's React entry (NIC-142), loaded by the native shell
 * at `index.html?surface=layoutpin` into its own top-most borderless `NSWindow`,
 * dropped just above the bottom-bar "+". The dashboard is a strict backdrop, so the
 * picker must be a real window that can sit above the open layout windows — the same
 * reasoning as the More Apps launcher (backdrop-policy decision, 2026-07-06).
 *
 * Renders the {@link LayoutPinPicker} filling the window (its themed bar + × replace
 * native chrome). Its adds are session-only (`addLayoutTarget`); the ×, Escape, or
 * the scrim post `shellControl.closeLayoutPin`, so the native shell owns the window's
 * lifecycle. Unlike More Apps it stays open across adds (pin several hotswaps).
 */
export function LayoutPinApp() {
  return (
    <BridgeProvider bridge={bridge}>
      <DashboardStateProvider store={store}>
        <AppearanceProvider>
          <ThemeProvider>
            <div className="pin-pop-window" role="main" aria-label="Add a layout window">
              <LayoutPinPicker
                variant="standalone"
                onClose={() => postShellControl("closeLayoutPin")}
              />
            </div>
          </ThemeProvider>
        </AppearanceProvider>
      </DashboardStateProvider>
    </BridgeProvider>
  );
}

export default LayoutPinApp;
