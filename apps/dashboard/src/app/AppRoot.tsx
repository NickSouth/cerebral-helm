import "../tokens/tokens.css";
import "../app.css";
import "../styles/responsive.css";
import "../shell/shell.css";
import { DashboardShell } from "../shell/DashboardShell";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { ThemeProvider } from "./ThemeProvider";
import { createBootstrapStore } from "../state/bootstrapStore";

const store = createBootstrapStore();

/**
 * The application container: owns state (the store seam), theme application, and the
 * accessibility baseline (skip link), and renders the three-zone shell (NIC-53).
 */
export function AppRoot() {
  return (
    <DashboardStateProvider store={store}>
      <ThemeProvider>
        <a className="skip-link" href="#main">
          Skip to main content
        </a>
        <DashboardShell />
      </ThemeProvider>
    </DashboardStateProvider>
  );
}

export default AppRoot;
