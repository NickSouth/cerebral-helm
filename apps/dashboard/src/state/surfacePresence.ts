import { useSyncExternalStore } from "react";

/**
 * Surface presence (NIC-152): is this dashboard surface the thing the user is looking at, or is
 * it acting as backdrop behind their real work?
 *
 * **This is a per-surface fact, not an app-wide one.** With a dashboard on every display, the
 * laptop screen can be showing nothing but CerebralHelm — where it should stay fully present —
 * while the external display has windows stacked over its dashboard and should recede. One
 * global "is the app focused" boolean cannot express two displays in different states, which is
 * why the trigger is occupancy of *this* surface's display rather than application focus.
 * (This supersedes NIC-152's original "focus loss/gain, not window-overlap" note — owner
 * decision, 2026-08-05.) App focus would also be a poor signal regardless: the backdrop window
 * is borderless, sub-normal-level and non-activating by policy, so it is built never to take key
 * focus, and its webview's `focus`/`blur` events say little about what the user is doing.
 *
 * The authority is therefore the **native shell**, which alone can see the windows on each
 * display, and which pushes the value in per surface. The browser fallback below exists so the
 * treatment can be developed and tuned without the Mac host — the moment the native side speaks,
 * it wins permanently.
 *
 * A module-level store rather than a provider: nine surfaces mount their own React trees, and
 * presence is ambient to all of them. `useSyncExternalStore` keeps it out of every tree's props.
 */

interface PresenceWindow extends Window {
  /**
   * The native shell's channel into this surface. `DashboardWebView` evaluates
   * `window.__cerebralPresence?.set(<bool>)` whenever the windows on this surface's display
   * change — the same shape of per-surface injection already used for `--ch-safe-area-top`
   * (NIC-155). If the native side would rather deliver this as a bridge event, only this file
   * changes; nothing that renders the treatment knows where the value came from.
   */
  __cerebralPresence?: { set(receded: boolean): void };
}

let receded = false;
/** Once the native shell has spoken, browser focus events stop being consulted, permanently. */
let nativeDriven = false;
let installed = false;
const listeners = new Set<() => void>();

function publish(next: boolean): void {
  if (receded === next) {
    return;
  }
  receded = next;
  for (const listener of [...listeners]) {
    listener();
  }
}

/** The native shell's setter — authoritative, and it locks out the browser fallback. */
function setFromNative(next: boolean): void {
  nativeDriven = true;
  publish(next);
}

/**
 * Development fallback: treat losing window focus as receding. A rough stand-in for "something
 * else is on this display", good enough to build and tune the treatment against, and never used
 * once the host is driving.
 */
function setFromBrowser(next: boolean): void {
  if (nativeDriven) {
    return;
  }
  publish(next);
}

function install(): void {
  if (installed || typeof window === "undefined") {
    return;
  }
  installed = true;
  (window as PresenceWindow).__cerebralPresence = { set: setFromNative };
  window.addEventListener("blur", () => setFromBrowser(true));
  window.addEventListener("focus", () => setFromBrowser(false));
  // Seed from the current state so a surface that mounts while already backgrounded starts
  // receded rather than snapping there on the next event.
  if (typeof document !== "undefined" && typeof document.hasFocus === "function") {
    setFromBrowser(!document.hasFocus());
  }
}

// Installed at module load, not on first subscribe.
//
// The native shell pushes the first value as soon as its occupancy observer has read the desktop,
// which can land before React has mounted anything that subscribes. If the hook only appeared on
// subscription, that first push would hit `undefined` and be dropped — and because the observer
// only reports *changes*, a display that was already covered at launch would stay looking present
// until something else moved. Existing from the moment the bundle evaluates removes the race
// rather than papering over it with a replay.
install();

function subscribe(listener: () => void): () => void {
  install();
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

/**
 * True when this surface should recede: dimmed, desaturated, softened, and quieted.
 * Server/jsdom render as present — never start a surface in the receded state.
 */
export function useSurfaceReceded(): boolean {
  return useSyncExternalStore(
    subscribe,
    () => receded,
    () => false
  );
}

/** Test seam: drive presence directly without a window event. */
export function __setSurfaceRecededForTest(next: boolean): void {
  publish(next);
}
