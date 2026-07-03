import { useCallback, useEffect } from "react";
import "../tokens/tokens.css";
import "../app.css";
import "../shell/shell.css";
import "./palette.css";
import { CommandSurface } from "../shell/CommandSurface";
import {
  createWKWebViewCerebralBridge,
  isNativeBridgeAvailable
} from "../bridge/wkWebViewCerebralBridge";

/**
 * The floating command palette's React entry (NIC-75 / FR-SHL-02), loaded by the native
 * shell at `index.html?surface=palette` into a lightweight WKWebView inside an `NSPanel`.
 *
 * It reuses the existing `CommandSurface` (token/visual parity, owner decision) and
 * submits through the **same** live bridge as the dashboard — `submitCommand` runs on the
 * one shared runtime, never a forked one. A private `paletteControl` channel asks the
 * native side to dismiss on submit or Escape. Executing a command dismisses the palette;
 * the "Ask Heimlich → dashboard center panel" routing is NIC-76 window-role work.
 */

// The shell registers the native bridge transport; in a plain browser preview there is
// none, so the input still renders and submit is a no-op.
const bridge = isNativeBridgeAvailable() ? createWKWebViewCerebralBridge() : null;

interface PaletteControlWindow extends Window {
  webkit?: { messageHandlers?: { paletteControl?: { postMessage(message: unknown): void } } };
  __cerebralFocusPalette?: () => void;
}

function paletteControl(action: string): void {
  (window as PaletteControlWindow).webkit?.messageHandlers?.paletteControl?.postMessage({ action });
}

export function CommandPaletteApp() {
  useEffect(() => {
    // The native side calls this on every summon so the pre-warmed (previously hidden)
    // webview focuses its input immediately.
    (window as PaletteControlWindow).__cerebralFocusPalette = () => {
      const input = document.querySelector<HTMLInputElement>(".command-palette input");
      input?.focus();
      input?.select();
    };
    function onKeyDown(event: KeyboardEvent): void {
      if (event.key === "Escape") {
        paletteControl("dismiss");
      }
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  const onSubmit = useCallback((text: string) => {
    // Fire-and-forget: failures surface through the dashboard's event stream, not here.
    // The `hotkey` source keeps the command bus honest about provenance (FR-CMD-01).
    bridge?.submitCommand({ rawInput: text, source: "hotkey" }).catch(() => {});
    paletteControl("dismiss");
  }, []);

  // Default mode theming (executive) so the mode-accent tokens resolve; syncing the
  // palette to the active mode is later window-role/visual work.
  return (
    <div className="command-palette" data-mode="executive">
      <CommandSurface
        variant="launcher"
        placeholder="Ask Heimlich or type a command…"
        ariaLabel="Command palette"
        onSubmit={onSubmit}
        autoFocus
      />
    </div>
  );
}

export default CommandPaletteApp;
