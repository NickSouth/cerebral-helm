import "../tokens/tokens.css";
import "../app.css";
import "../styles/responsive.css";
import "../shell/shell.css";
import { ProjectDetail } from "../shell/ProjectDetail";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { BridgeProvider } from "../state/BridgeProvider";
import { AppearanceProvider } from "../state/AppearanceProvider";
import { ThemeProvider } from "./ThemeProvider";
import { postShellControl } from "../shell/shellControl";
import { submitSetProjectImportance } from "../shell/openProjectDetail";
import { createDashboardRuntime } from "../state/bootstrapStore";

/** The per-project payload the native shell injects before load (NIC-129, Increment 5). */
interface ProjectDetailPayload {
  path: string;
  name: string;
  markdownBody: string;
  importance: number;
}
interface ProjectDetailWindow extends Window {
  __cerebralProjectDetail?: ProjectDetailPayload;
}

// The same runtime seam as the other surfaces: the live WKWebView bridge inside the native
// shell (for theming/appearance), the mock in a plain browser preview. Its bridge claims the
// singleton `window.__cerebralReceive`, so only the active surface's module may run (main.tsx).
const runtime = createDashboardRuntime();

// The project data rides alongside the shared bootstrap as its own global, so the shared
// `composeBootstrapState()` contract stays free of per-project fields (NIC-129 decision).
const detail: ProjectDetailPayload =
  (typeof window !== "undefined" ? (window as ProjectDetailWindow).__cerebralProjectDetail : undefined) ?? {
    path: "",
    name: "Project",
    markdownBody: "",
    importance: 0
  };

/**
 * The project detail window's React entry (NIC-129), loaded by the native shell at
 * `index.html?surface=projectdetail` into its own `NSWindow` (Increment 5). Renders the
 * project's `PROJECT.md` and the live-status placeholder; the × posts
 * `shellControl.closeProjectDetail` so the native shell owns the window's lifecycle.
 */
export function ProjectDetailApp() {
  return (
    <BridgeProvider bridge={runtime.bridge}>
      <DashboardStateProvider store={runtime.store}>
        <AppearanceProvider>
          <ThemeProvider>
            <ProjectDetail
              name={detail.name}
              markdownBody={detail.markdownBody}
              importance={detail.importance}
              onClose={() => postShellControl("closeProjectDetail")}
              onSetImportance={(value) => submitSetProjectImportance(detail.path, value)}
            />
          </ThemeProvider>
        </AppearanceProvider>
      </DashboardStateProvider>
    </BridgeProvider>
  );
}

export default ProjectDetailApp;
