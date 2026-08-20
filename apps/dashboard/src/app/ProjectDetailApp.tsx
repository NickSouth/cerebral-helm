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
import {
  submitSetProjectImportance,
  submitSetProjectLinearProject
} from "../shell/openProjectDetail";
import { createDashboardRuntime } from "../state/bootstrapStore";

/** The per-project payload the native shell injects before load (NIC-129, Increment 5). */
interface ProjectDetailPayload {
  path: string;
  name: string;
  markdownBody: string;
  importance: number;
  /** The Linear project this folder tracks, by name (NIC-221), or null when unlinked — which is
   *  a normal state, not an error. Always present as an explicit null rather than omitted. */
  linearProject: string | null;
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
//
// The fallback is the BROWSER-PREVIEW seam, the same role `mockCerebralBridge` plays for the
// bridge: inside the native shell the global is always injected, so this branch is unreachable
// there. It carries a representative project rather than an empty one so the surface can actually
// be looked at during development — an empty body and a null link render two states out of the
// section's six, and neither is the one worth judging.
const detail: ProjectDetailPayload =
  (typeof window !== "undefined" ? (window as ProjectDetailWindow).__cerebralProjectDetail : undefined) ?? {
    path: "",
    name: "CerebralHelm",
    markdownBody: [
      "# CerebralHelm",
      "",
      "_A local-first personal command layer for macOS, driven by the assistant Heimlich._",
      "",
      "## Focus",
      "",
      "- Local LLM integration — the model provider port and the passive tier",
      "- Minor features and fixes on the shipped v1.0.0 app",
      "",
      "## Notes",
      "",
      "Shipped 2026-08-10 and in daily personal use."
    ].join("\n"),
    importance: 10,
    linearProject: "CerebralHelm"
  };

/**
 * The project detail window's React entry (NIC-129), loaded by the native shell at
 * `index.html?surface=projectdetail` into its own `NSWindow` (Increment 5). Renders the
 * project's `PROJECT.md` and its live Linear cycle; the × posts
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
              linearProject={detail.linearProject}
              onClose={() => postShellControl("closeProjectDetail")}
              onSetImportance={(value) => submitSetProjectImportance(detail.path, value)}
              onSetLinearProject={(project) =>
                submitSetProjectLinearProject(detail.path, project)
              }
            />
          </ThemeProvider>
        </AppearanceProvider>
      </DashboardStateProvider>
    </BridgeProvider>
  );
}

export default ProjectDetailApp;
