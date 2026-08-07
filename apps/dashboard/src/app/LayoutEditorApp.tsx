import "../tokens/tokens.css";
import "../app.css";
import "../styles/responsive.css";
import "../shell/shell.css";
import "../shell/settings/settings.css";
import { LayoutEditor } from "../shell/settings/LayoutEditor";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { useDashboardState } from "../state/DashboardStateProvider";
import { BridgeProvider } from "../state/BridgeProvider";
import { AppearanceProvider } from "../state/AppearanceProvider";
import { ThemeProvider } from "./ThemeProvider";
import { postShellControl } from "../shell/shellControl";
import { humanizeId } from "../shell/labels";
import { createDashboardRuntime } from "../state/bootstrapStore";

// The same runtime seam as AppRoot: the live WKWebView bridge inside the native
// shell (seeded from the injected bootstrap), the mock in a plain browser preview.
const runtime = createDashboardRuntime();
const bridge = runtime.bridge;
const store = runtime.store;

/** The mode whose layout this window edits, from `?surface=layouteditor&mode=<id>`. */
const editModeId =
  typeof window !== "undefined"
    ? (new URLSearchParams(window.location.search).get("mode") ?? "developer")
    : "developer";

/** Resolves the mode's display label from the bootstrap-seeded modes, then renders the
 *  standalone editor. Kept inside the providers so it can read the store. */
function LayoutEditorWindowBody() {
  const { modes } = useDashboardState();
  const label = modes.find((mode) => mode.id === editModeId)?.label ?? humanizeId(editModeId);
  return (
    <LayoutEditor
      modeId={editModeId}
      label={label}
      variant="standalone"
      onClose={() => postShellControl("closeLayoutEditor")}
    />
  );
}

/**
 * The layout editor window's React entry (NIC-142), loaded by the native shell at
 * `index.html?surface=layouteditor&mode=<id>` into its own top-most frameless
 * `NSWindow` (the same "own window" treatment as More Apps / Settings — the dashboard
 * is a strict backdrop, so a substantial editor must be a real window). Renders the
 * {@link LayoutEditor} in its standalone variant filling the window; the × posts
 * `shellControl.closeLayoutEditor` so the native shell owns the window's lifecycle.
 * Increments 5–6 replace the capture flow with a drag/resize canvas + a picker.
 */
export function LayoutEditorApp() {
  return (
    <BridgeProvider bridge={bridge}>
      <DashboardStateProvider store={store}>
        <AppearanceProvider>
          <ThemeProvider>
            <div className="layout-editor-window" role="main" aria-label="Edit layout">
              <LayoutEditorWindowBody />
            </div>
          </ThemeProvider>
        </AppearanceProvider>
      </DashboardStateProvider>
    </BridgeProvider>
  );
}

export default LayoutEditorApp;
