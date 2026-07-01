import { flushSync } from "react-dom";
import type { DashboardStore } from "../state/dashboardState";

/**
 * The mode wave (course-correction D.1, animated mode switch): when the user clicks a mode
 * control, the theme change PROPAGATES outward from that control instead of flipping in place.
 * Implemented as a View Transition — the old render is held while the new render (already
 * wearing the target palette via data-mode) is revealed by a circle expanding from the clicked
 * control, with an accent ring riding the reveal edge (`.mode-wave-ring`, app.css).
 *
 * This is the precedent-setter for spatial transitions: animate the REVEAL of the final state
 * from the control that caused it; never animate intermediate theme states.
 *
 * Honest fallbacks, in order: no armed origin (the mode changed without a click), no
 * `document.startViewTransition`, no Web Animations, or stilled motion (OS preference or the
 * NIC-63 override) → plain notify, which keeps the existing token cross-fade (shell.css).
 */

/** A click origin is only good for the switch it triggered — expire it if no event follows. */
const ORIGIN_TTL_MS = 2000;
/** Noticeable but not load-bearing (owner intent); longer than --ch-motion-slow on purpose. */
const WAVE_DURATION_MS = 600;
/** --ch-ease-standard; the Web Animations API cannot resolve CSS custom properties. */
const WAVE_EASING = "cubic-bezier(0.2, 0, 0, 1)";

interface ViewTransitionLike {
  readonly ready: Promise<void>;
  readonly finished: Promise<void>;
}

type DocumentWithViewTransition = Document & {
  startViewTransition?: (update: () => void) => ViewTransitionLike;
};

let pendingOrigin: { x: number; y: number; armedAt: number } | null = null;
/** Concurrent-wave guard (rapid re-clicks): only the LAST wave to finish removes the class. */
let activeWaves = 0;

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

function waveCapable(): boolean {
  return (
    typeof document !== "undefined" &&
    typeof (document as DocumentWithViewTransition).startViewTransition === "function" &&
    typeof document.documentElement.animate === "function" &&
    !motionStilled()
  );
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
  if (!origin || !waveCapable()) {
    notify();
    return;
  }

  const root = document.documentElement;
  // While the wave runs, revealed pixels must already wear the final palette — this class
  // suspends the per-property cross-fades (app.css) so the wavefront carries the change.
  activeWaves += 1;
  root.classList.add("mode-wave");
  let cleaned = false;
  const cleanup = () => {
    if (cleaned) {
      return;
    }
    cleaned = true;
    activeWaves -= 1;
    if (activeWaves === 0) {
      root.classList.remove("mode-wave");
    }
  };

  let committed = false;
  const commit = () => {
    if (!committed) {
      committed = true;
      // The DOM must change inside the transition callback for the browser to capture it.
      flushSync(notify);
    }
  };

  let transition: ViewTransitionLike;
  try {
    transition = (document as DocumentWithViewTransition).startViewTransition!(commit);
  } catch {
    cleanup();
    if (!committed) {
      notify();
    }
    return;
  }

  transition.ready
    .then(() => {
      const radius = Math.hypot(
        Math.max(origin.x, window.innerWidth - origin.x),
        Math.max(origin.y, window.innerHeight - origin.y)
      );
      root.animate(
        {
          clipPath: [
            `circle(0px at ${origin.x}px ${origin.y}px)`,
            `circle(${radius}px at ${origin.x}px ${origin.y}px)`
          ]
        },
        { duration: WAVE_DURATION_MS, easing: WAVE_EASING, pseudoElement: "::view-transition-new(root)" }
      );
      spawnWaveRing(origin.x, origin.y, radius);
    })
    .catch(() => {
      // The browser skipped the transition (e.g. another one superseded it); state already
      // committed via the callback — nothing visual to recover.
    });
  transition.finished.then(cleanup, cleanup);
}

/**
 * Store decorator (app-layer composition, AppRoot): re-notifies subscribers unchanged, except
 * when a notification carries a mode change — then the React commit runs inside the wave's
 * view transition. The store seam (getState + subscribe) is untouched for consumers, and the
 * reducer/bridge stay DOM-free.
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
