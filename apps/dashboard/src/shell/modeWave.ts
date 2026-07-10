import type { DashboardStore } from "../state/dashboardState";

/**
 * The mode wave (course-correction D.1, animated mode switch): clicking a mode control pulses a
 * glowing ring outward from that control while the dashboard re-themes. The theme change is a
 * LIVE commit — the per-property token cross-fade (shell.css) eases every accent over
 * `--ch-motion-slow` — so the Heimlich consciousness stream and the rest of the UI keep rendering
 * throughout.
 *
 * It is deliberately NOT a View Transition: a VT snapshots the whole page, which froze the WebGL
 * stream for the transition's duration (NIC-125). The reveal is now the ring + the token
 * cross-fade, never a held snapshot. This is still the precedent-setter for spatial transitions:
 * emanate from the control that caused the change; never animate intermediate theme states.
 *
 * Honest fallbacks: no armed origin (the mode changed without a click) or stilled motion (OS
 * preference or the NIC-63 override) → plain notify, which still cross-fades the tokens (or snaps
 * them instantly under reduced motion, where `--ch-motion-*` is 0ms).
 */

/** A click origin is only good for the switch it triggered — expire it if no event follows. */
const ORIGIN_TTL_MS = 2000;
/** Noticeable but not load-bearing (owner intent); longer than --ch-motion-slow on purpose. */
const WAVE_DURATION_MS = 600;
/** --ch-ease-standard; the Web Animations API cannot resolve CSS custom properties. */
const WAVE_EASING = "cubic-bezier(0.2, 0, 0, 1)";

let pendingOrigin: { x: number; y: number; armedAt: number } | null = null;

/** Arm the next mode switch to wave out from this viewport point (the clicked control's center). */
export function armModeWave(x: number, y: number): void {
  pendingOrigin = { x, y, armedAt: Date.now() };
}

function consumeOrigin(): { x: number; y: number } | null {
  const origin = pendingOrigin;
  pendingOrigin = null;
  return origin && Date.now() - origin.armedAt <= ORIGIN_TTL_MS ? origin : null;
}

/** Either the OS preference or the app-level override (NIC-63) stills the wave entirely. */
function motionStilled(): boolean {
  if (window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches) {
    return true;
  }
  return document.querySelector(".app-root")?.getAttribute("data-reduced-motion") === "true";
}

/** The Web Animations API drives the ring; absent it (jsdom), we skip the flourish, not the switch. */
function canAnimate(): boolean {
  return typeof document !== "undefined" && typeof document.documentElement.animate === "function";
}

/** The glowing leading edge: appended under `.app-root` so it inherits the TARGET mode accent. */
function spawnWaveRing(x: number, y: number, radius: number): void {
  const host = document.querySelector(".app-root");
  if (!host) {
    return;
  }
  const ring = document.createElement("div");
  ring.className = "mode-wave-ring";
  ring.style.left = `${x}px`;
  ring.style.top = `${y}px`;
  host.appendChild(ring);
  const sweep = ring.animate(
    [
      { width: "0px", height: "0px", opacity: 0.95 },
      { opacity: 0.8, offset: 0.7 },
      { width: `${radius * 2}px`, height: `${radius * 2}px`, opacity: 0 }
    ],
    { duration: WAVE_DURATION_MS, easing: WAVE_EASING }
  );
  const remove = () => ring.remove();
  sweep.finished.then(remove, remove);
}

function runModeWave(notify: () => void): void {
  const origin = consumeOrigin();
  // Commit the mode change live so the whole UI — the WebGL stream included — keeps rendering and
  // the tokens cross-fade to the new palette. The ring is the only added flourish, spawned after
  // the commit so it already wears the target mode's accent.
  notify();
  if (origin && !motionStilled() && canAnimate()) {
    const radius = Math.hypot(
      Math.max(origin.x, window.innerWidth - origin.x),
      Math.max(origin.y, window.innerHeight - origin.y)
    );
    spawnWaveRing(origin.x, origin.y, radius);
  }
}

/**
 * Store decorator (app-layer composition, AppRoot): re-notifies subscribers unchanged, except
 * when a notification carries a mode change — then the ring rides the live commit. The store seam
 * (getState + subscribe) is untouched for consumers, and the reducer/bridge stay DOM-free.
 */
export function withModeWave(store: DashboardStore): DashboardStore {
  let lastMode = store.getState().mode;
  const listeners = new Set<() => void>();
  const notify = () => {
    // Snapshot so a listener that unsubscribes mid-dispatch can't mutate the live set.
    for (const listener of [...listeners]) {
      listener();
    }
  };

  store.subscribe(() => {
    const mode = store.getState().mode;
    const modeChanged = mode !== lastMode;
    lastMode = mode;
    if (modeChanged) {
      runModeWave(notify);
    } else {
      notify();
    }
  });

  return {
    getState: store.getState,
    subscribe(listener) {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    }
  };
}
