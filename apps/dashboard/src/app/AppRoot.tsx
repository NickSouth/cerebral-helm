import "../tokens/tokens.css";
import "../app.css";
import "../styles/responsive.css";
import "../shell/shell.css";
import { DashboardShell } from "../shell/DashboardShell";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { BridgeProvider } from "../state/BridgeProvider";
import { ThemeProvider } from "./ThemeProvider";
import { createDashboardRuntime } from "../state/bootstrapStore";

const { bridge, store } = createDashboardRuntime();

/**
 * The application container: owns the bridge + state store (the read/write seam), theme
 * application, and the accessibility baseline (skip link), and renders the three-zone shell.
 */
export function AppRoot() {
  return (
    <BridgeProvider bridge={bridge}>
      <DashboardStateProvider store={store}>
        <ThemeProvider>
          <a className="skip-link" href="#main">
            Skip to main content
          </a>
          <DashboardShell />
        </ThemeProvider>
      </DashboardStateProvider>
    </BridgeProvider>
  );
}

export default AppRoot;
