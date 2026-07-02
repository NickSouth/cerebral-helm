import "../tokens/tokens.css";
import "../app.css";
import "../styles/responsive.css";
import "../shell/shell.css";
import "../shell/settings/settings.css";
import { DashboardShell } from "../shell/DashboardShell";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { BridgeProvider } from "../state/BridgeProvider";
import { ConversationProvider } from "../state/ConversationProvider";
import { SettingsProvider } from "../state/SettingsProvider";
import { AppearanceProvider } from "../state/AppearanceProvider";
import { ThemeProvider } from "./ThemeProvider";
import { createDashboardRuntime, readStateNameFromLocation } from "../state/bootstrapStore";
import { withModeWave } from "../shell/modeWave";

// `?state=offline|loading|error|recovery` seeds a degraded state for preview/screenshots (NIC-64).
const runtime = createDashboardRuntime({ stateName: readStateNameFromLocation() });
const bridge = runtime.bridge;
// Mode switches commit inside the wave's view transition (shell/modeWave.ts); everything else
// notifies straight through. Composed here — the app layer — so state/bridge stay DOM-free.
const store = withModeWave(runtime.store);

/**
 * The application container: owns the bridge + state store (the read/write seam), the Heimlich
 * conversation session, theme application, and the accessibility baseline (skip link), and
 * renders the three-zone shell.
 */
export function AppRoot() {
  return (
    <BridgeProvider bridge={bridge}>
      <DashboardStateProvider store={store}>
        <AppearanceProvider>
          <ThemeProvider>
            <ConversationProvider>
              <SettingsProvider>
                <a className="skip-link" href="#main">
                  Skip to main content
                </a>
                <DashboardShell />
              </SettingsProvider>
            </ConversationProvider>
          </ThemeProvider>
        </AppearanceProvider>
      </DashboardStateProvider>
    </BridgeProvider>
  );
}

export default AppRoot;
