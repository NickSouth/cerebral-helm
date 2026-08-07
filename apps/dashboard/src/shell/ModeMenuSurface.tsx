import { useEffect } from "react";
import { useDashboardState } from "../state/DashboardStateProvider";
import { useBridge } from "../state/BridgeProvider";
import { postShellControl } from "./shellControl";
import { ModeGlyph } from "./ModeGlyph";

/**
 * The mode-swap dropdown's content (NIC-144), hosted by the native shell at
 * `index.html?surface=modemenu` inside a transparent, top-most window that layers
 * ABOVE open apps — the bottom bar's in-backdrop menu could never rise above other
 * windows (the dashboard is a strict never-lift backdrop). Selecting a mode switches
 * it through the shared bridge (same path as the dashboard) and closes the window;
 * Escape closes it too. The window's transparency lets the menu grow up + fade in
 * (see `.mode-menu-surface` in shell.css) so it reads as emerging from the bar.
 */
export function ModeMenuSurface() {
  const { mode, modes } = useDashboardState();
  const bridge = useBridge();

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent): void {
      if (event.key === "Escape") {
        postShellControl("closeModeMenu");
      }
    }
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, []);

  function selectMode(modeId: string, active: boolean): void {
    if (!active) {
      void bridge.applyMode({ modeId });
    }
    // Every selection dismisses the dropdown — the native shell owns its lifecycle.
    postShellControl("closeModeMenu");
  }

  return (
    <div className="mode-menu-surface">
      <ul
        className="bottom-bar__mode-menu mode-menu-surface__menu"
        role="menu"
        aria-label="Switch mode"
      >
        {modes.map((modeView) => {
          const active = modeView.label === mode;
          return (
            <li key={modeView.id} role="none">
              <button
                type="button"
                role="menuitemradio"
                aria-checked={active}
                className="bottom-bar__mode-option"
                data-active={active}
                onClick={() => selectMode(modeView.id, active)}
              >
                <span className="bottom-bar__mode-option-icon" aria-hidden="true">
                  <ModeGlyph mode={modeView.id} />
                </span>
                {modeView.label}
              </button>
            </li>
          );
        })}
      </ul>
    </div>
  );
}

export default ModeMenuSurface;
