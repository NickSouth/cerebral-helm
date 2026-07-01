import "../tokens/tokens.css";
import "../app.css";
import "../styles/responsive.css";
import "../shell/shell.css";
import { DashboardShell } from "../shell/DashboardShell";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { BridgeProvider } from "../state/BridgeProvider";
import { ConversationProvider } from "../state/ConversationProvider";
import { ThemeProvider } from "./ThemeProvider";
import { createDashboardRuntime, readStateNameFromLocation } from "../state/bootstrapStore";

// `?state=offline|loading|error|recovery` seeds a degraded state for preview/screenshots (NIC-64).
const { bridge, store } = createDashboardRuntime({ stateName: readStateNameFromLocation() });

/**
 * The application container: owns the bridge + state store (the read/write seam), the Heimlich
 * conversation session, theme application, and the accessibility baseline (skip link), and
 * renders the three-zone shell.
 */
export function AppRoot() {
  return (
    <BridgeProvider bridge={bridge}>
      <DashboardStateProvider store={store}>
        <ThemeProvider>
          <ConversationProvider>
            <a className="skip-link" href="#main">
              Skip to main content
            </a>
            <DashboardShell />
          </ConversationProvider>
        </ThemeProvider>
      </DashboardStateProvider>
    </BridgeProvider>
  );
}

export default AppRoot;
