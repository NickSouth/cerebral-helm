import "../tokens/tokens.css";
import "../app.css";
import "../styles/responsive.css";
import "../shell/shell.css";
import { WindowNavigator } from "../shell/WindowNavigator";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { BridgeProvider } from "../state/BridgeProvider";
import { AppearanceProvider } from "../state/AppearanceProvider";
import { useRef } from "react";
import { ThemeProvider } from "./ThemeProvider";
import { useTransparentSurface } from "./useTransparentSurface";
import { useGlassGeometry } from "./useGlassGeometry";
import { postShellControl } from "../shell/shellControl";
import { createDashboardRuntime } from "../state/bootstrapStore";

// The same runtime seam as AppRoot: the live WKWebView bridge inside the native shell
// (seeded from the injected bootstrap), the mock in a plain browser preview.
const runtime = createDashboardRuntime();
const bridge = runtime.bridge;
const store = runtime.store;

/**
 * The window-navigator window's React entry (NIC-143), loaded by the native shell at
 * `index.html?surface=windownavigator` into its own top-most floating `NSWindow`. The
 * dashboard is a strict backdrop, so the navigator must be a real window that can sit
 * above other apps' windows — the same reasoning as the More Apps launcher.
 *
 * Fills the window with the standalone {@link WindowNavigator}; every close path (the ×,
 * Escape, or an accepted surface) posts `shellControl.closeWindowNavigator`, so the
 * native shell owns the window's lifecycle.
 */
export function WindowNavigatorApp() {
  useTransparentSurface();
  const rootRef = useRef<HTMLDivElement>(null);
  // The header and each window card are the glass here — there is no grouping pane in this surface,
  // so the boxes sit straight on the transparent surface and each gets its own blur.
  useGlassGeometry(rootRef, ".win-nav__header, .win-nav__card");

  return (
    <BridgeProvider bridge={bridge}>
      <DashboardStateProvider store={store}>
        <AppearanceProvider>
          <ThemeProvider>
            <div className="win-nav-window" role="main" aria-label="Open windows" ref={rootRef}>
              <WindowNavigator
                variant="standalone"
                onClose={() => postShellControl("closeWindowNavigator")}
              />
            </div>
          </ThemeProvider>
        </AppearanceProvider>
      </DashboardStateProvider>
    </BridgeProvider>
  );
}

export default WindowNavigatorApp;
