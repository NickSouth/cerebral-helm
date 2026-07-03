import { useCallback, useEffect } from "react";
import "../tokens/tokens.css";
import "../app.css";
import "../shell/shell.css";
import "./palette.css";
import { CommandSurface } from "../shell/CommandSurface";
import { usePaletteMode } from "./usePaletteMode";
import {
  createWKWebViewCerebralBridge,
  isNativeBridgeAvailable
} from "../bridge/wkWebViewCerebralBridge";

/**
 * The floating command palette's React entry (NIC-75/76, FR-SHL-02/04), loaded by the
 * native shell at `index.html?surface=palette` into a lightweight WKWebView inside an
 * `NSPanel`.
 *
 * It reuses the existing `CommandSurface` (token/visual parity, owner decision). A
 * submission routes to the dashboard's **center-panel conversation** ("Ask Heimlich"):
 * the palette posts `askHeimlich` on the private `paletteControl` channel, and the native
 * coordinator dismisses the palette, brings the dashboard forward, and opens the
 * conversation (which dispatches the command through the shared bridge). Escape / click
 * dismiss. The palette re-themes to the active mode via `config.changed` (Increment 3).
 */

// The shell registers the native bridge transport; in a plain browser preview there is
// none, so the input still renders and submit posts to a no-op channel.
const bridge = isNativeBridgeAvailable() ? createWKWebViewCerebralBridge() : null;

interface PaletteControlWindow extends Window {
  webkit?: { messageHandlers?: { paletteControl?: { postMessage(message: unknown): void } } };
  __cerebralFocusPalette?: () => void;
}

function paletteControl(action: string, payload: Record<string, unknown> = {}): void {
  (window as PaletteControlWindow).webkit?.messageHandlers?.paletteControl?.postMessage({
    action,
    ...payload
  });
}

export function CommandPaletteApp() {
  const mode = usePaletteMode(bridge);

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
    // Route to the dashboard's Ask-Heimlich conversation; the coordinator dismisses the
    // palette, brings the dashboard forward, and opens the conversation (which dispatches
    // the command through the shared bridge). Inline command execution without surfacing
    // the dashboard is a later refinement (tied to reachable app-launch commands).
    paletteControl("askHeimlich", { text });
  }, []);

  return (
    <div className="command-palette" data-mode={mode}>
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
