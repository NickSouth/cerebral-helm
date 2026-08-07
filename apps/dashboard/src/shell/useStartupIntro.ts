import { useEffect, useSyncExternalStore } from "react";

/**
 * The launch sequence (NIC-157). CerebralHelm starts at login and is rarely restarted, so this is
 * a deliberately unhurried set-piece rather than a quick reveal (owner decision, 2026-08-05):
 *
 *   1. the background colour alone
 *   2. a single thread draws itself in from the left edge, all the way across
 *   3. more threads fly in from both sides, thickening into the bundle
 *   4. the field contracts into its resting band
 *   5. the Heimlich panel pops up around it
 *   6. centre chrome, rails, header and bottom bar settle in
 *
 * Steps 2–4 belong to the WebGL field and are choreographed in the shader — they are motion of
 * the threads themselves, which CSS cannot reach. Steps 5–6 are the CSS stagger in shell.css.
 * The two halves are timed by the same `--ch-intro-*` tokens so they stay one sequence.
 *
 * `FIELD_DURATION_MS` must equal `--ch-intro-delay-window` + `--ch-intro-window`, i.e. the moment
 * the panel finishes pinching in. The field's contraction and the panel's are the same beat, so
 * the shader's clock has to run until the box stops moving — ending it earlier leaves the field
 * visibly motionless for the remainder of the pinch, because the resting flow is far too slow to
 * register over that span.
 *
 * `TOTAL_MS` must outlast the last CSS delay plus its duration — it only decides when the driving
 * attribute is dropped, so finishing early would make the final regions snap.
 */
export const FIELD_DURATION_MS = 4920;
export const TOTAL_MS = 6200;

/**
 * Once per page load, not once per mount. A mode switch re-renders the shell and StrictMode
 * double-invokes effects in development; neither is a launch, and replaying would make the app
 * look like it was restarting. Module scope is the right lifetime — the native shell loads this
 * bundle once per app launch, so "first run in this module" IS "startup". Each surface's webview
 * is its own module instance, so every display plays its own sequence.
 */
let startedAt: number | null = null;
let active = false;
const listeners = new Set<() => void>();

function publish(): void {
  for (const listener of [...listeners]) {
    listener();
  }
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

/**
 * Begin the sequence, at most once. Returns nothing — consumers read the state through the hooks
 * below, so the field and the shell cannot disagree about when startup began.
 */
function begin(): void {
  if (startedAt !== null) {
    return;
  }
  // The same clock `requestAnimationFrame` stamps its callbacks with, so the shader can derive
  // its own progress per frame without React re-rendering once per frame.
  startedAt = typeof performance !== "undefined" ? performance.now() : 0;
  active = true;
  publish();
  window.setTimeout(() => {
    active = false;
    publish();
  }, TOTAL_MS);
}

/**
 * Drives the sequence. Pass `ready` — true once real data has replaced the first-paint skeleton —
 * so the sequence introduces the actual dashboard rather than playing over a loading state and
 * leaving the shell to pop in afterwards.
 *
 * **Never gates interactivity.** This adds animations; it does not withhold rendering, disable
 * controls, or cover anything. Every control is live and hit-testable from the first frame, which
 * is what the ticket requires of an animation that runs at login. Under reduced motion the tokens
 * collapse to zero and the shader is handed a completed sequence, so it resolves instantly with
 * no bespoke guard here (matching the NIC-158 precedent).
 */
export function useStartupIntro(ready: boolean): boolean {
  useEffect(() => {
    if (ready) {
      begin();
    }
  }, [ready]);

  return useSyncExternalStore(
    subscribe,
    () => active,
    () => false
  );
}

/**
 * When the field's choreography began, on the `performance.now()` clock — or `null` if startup is
 * already over, which tells the shader to render its finished steady state immediately.
 */
export function useFieldIntroStart(): number | null {
  return useSyncExternalStore(
    subscribe,
    () => (active ? startedAt : null),
    () => null
  );
}

/** Test seam: forget that the sequence has played, so a case can drive it again. */
export function __resetStartupIntroForTest(): void {
  startedAt = null;
  active = false;
}
