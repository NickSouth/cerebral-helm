import "../tokens/tokens.css";
import "../app.css";
import "../styles/responsive.css";
import "../shell/shell.css";
import "./companion.css";
import { useRef } from "react";
import { HeimlichConsciousness } from "../shell/HeimlichConsciousness";
import { PersistentBottomBar } from "../shell/PersistentBottomBar";
import { useAmbientBeam } from "../shell/useAmbientBeam";
import { useStartupIntro } from "../shell/useStartupIntro";
import { useSurfaceReceded } from "../state/surfacePresence";
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
  const rootRef = useRef<HTMLDivElement>(null);
  // The companion's bottom bar renders a `BeamOverlay` like every other outlined surface, but
  // nothing was ever driving it here — `useAmbientBeam` ran only in `DashboardShell`, so the
  // secondary displays' tiles stayed parked off-screen and their bar never caught the light.
  // The driver is surface-local (it sweeps the viewport and reflects off whatever overlays it
  // finds beneath its root), so each display runs its own sweep rather than sharing the main
  // display's — which is correct: they are separate screens with separate geometry.
  useAmbientBeam(rootRef, useSurfaceReceded());
  // Secondary displays wake with the same sequence (NIC-157). Each webview is its own module
  // instance, so every screen runs its own copy rather than sharing the main display's clock —
  // they light up together because they launch together, not because anything synchronises them.
  // No skeleton gate here: the companion renders the field, which needs no bootstrap data.
  useStartupIntro(true);

  return (
    <BridgeProvider bridge={bridge}>
      <DashboardStateProvider store={store}>
        <AppearanceProvider>
          <ThemeProvider>
            <SettingsProvider>
              <div
                className="companion-root"
                role="main"
                aria-label="CerebralHelm companion"
                ref={rootRef}
              >
                {/* The stream recedes with the surface; the bottom bar stays present (NIC-152). */}
                <div className="companion-stage recede-target">
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
