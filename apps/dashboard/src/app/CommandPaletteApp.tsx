import { useCallback, useEffect } from "react";
import type { SuggestedCommand } from "../bridge/cerebralBridge";
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
 * submission routes to the dashboard's command bus: the palette posts `askHeimlich` on the
 * private `paletteControl` channel, and the native coordinator dismisses the palette, brings
 * the dashboard forward, and dispatches the command through the shared bridge (surfacing the
 * result in the dashboard's status line — the Heimlich chat was removed, NIC-124). Escape /
 * click dismiss. The palette re-themes to the active mode via `config.changed` (Increment 3).
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
      // Blur first: after a dismiss the input is often still document.activeElement, making a
      // bare .focus() a no-op that fires no focus event — React's `focused` state then stays
      // stale and the suggestion list never returns (NIC-77). Blur→focus forces a real event.
      input?.blur();
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

  // Report the palette's content height to the native shell so the window can size to just the bar
  // (and grow when the suggestion list appears) — the palette is a bare bar, not a fixed box (NIC-77).
  useEffect(() => {
    const el = document.querySelector<HTMLElement>(".command-palette");
    if (!el || typeof ResizeObserver === "undefined") return;
    let last = 0;
    const report = () => {
      const height = Math.ceil(el.getBoundingClientRect().height);
      if (height && height !== last) {
        last = height;
        paletteControl("resize", { height });
      }
    };
    const observer = new ResizeObserver(report);
    observer.observe(el);
    report();
    return () => observer.disconnect();
  }, []);

  const onSubmit = useCallback((text: string) => {
    // Route to the dashboard's command bus; the coordinator dismisses the palette, brings the
    // dashboard forward, and dispatches the command through the shared bridge (result surfaces
    // in the dashboard status line). Inline command execution without surfacing the dashboard
    // is a later refinement (tied to reachable app-launch commands). An executed suggestion
    // arrives here as its exact `command` grammar string (NIC-168).
    paletteControl("askHeimlich", { text });
  }, []);

  // Ranked suggestions over the live catalogs (NIC-168) through the palette's own bound
  // bridge transport. In a plain browser preview there is no bridge (and no bus behind
  // the bar), so the palette honestly stays a bare input.
  const fetchSuggestions = useCallback(
    (query: string): Promise<readonly SuggestedCommand[]> =>
      bridge
        ? bridge.suggestCommands({ query }).then((result) => result.suggestions)
        : Promise.resolve([]),
    []
  );

  return (
    <div className="command-palette" data-mode={mode}>
      <CommandSurface
        variant="launcher"
        placeholder="Type a command…"
        ariaLabel="Command palette"
        onSubmit={onSubmit}
        fetchSuggestions={fetchSuggestions}
        focusOnMount
        spotlight
      />
    </div>
  );
}

export default CommandPaletteApp;
