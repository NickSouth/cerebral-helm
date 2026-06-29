import "../tokens/tokens.css";
import "../app.css";
import "../styles/responsive.css";
import { App } from "../App";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { ThemeProvider } from "./ThemeProvider";
import { createBootstrapStore } from "../state/bootstrapStore";

const store = createBootstrapStore();

/**
 * The application container: owns state (the store seam), theme application, and the
 * accessibility baseline (skip link). It is NOT the three-zone visual shell — that is
 * NIC-53. It composes the providers around whatever content renders inside.
 */
export function AppRoot() {
  return (
    <DashboardStateProvider store={store}>
      <ThemeProvider>
        <a className="skip-link" href="#main">
          Skip to main content
        </a>
        <App />
      </ThemeProvider>
    </DashboardStateProvider>
  );
}

export default AppRoot;
