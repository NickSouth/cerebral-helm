import { useEffect, useRef, useState } from "react";

/** How long a centre surface takes to recede. One duration for all of them, so the greeting, a
 *  report and a form leave at the same rate and the centre reads as one surface changing its mind
 *  rather than three components swapping. Pairs with `--ch-exit` in the stylesheet. */
export const CENTER_EXIT_MS = 260;

/** The beat between the old surface being gone and the new one starting to write. Small, but the
 *  difference between a handover and a collision. */
export const CENTER_BEAT_MS = 60;

/**
 * True once `blocked` has been false for `delayMs` — and immediately, with no wait, if it was
 * never true in the first place.
 *
 * This is the second half of a handover, and the asymmetry is the whole point. When something is
 * on screen that has to leave first, the incoming surface owes it a beat. When the space is
 * *already* empty there is nothing to hand over from, and charging the delay anyway would make
 * every surface feel slow for a transition that never happened.
 */
export function useEnterAfter(blocked: boolean, delayMs: number = CENTER_BEAT_MS): boolean {
  const [entered, setEntered] = useState(!blocked);

  useEffect(() => {
    if (blocked) {
      setEntered(false);
      return;
    }
    const id = window.setTimeout(() => setEntered(true), delayMs);
    return () => window.clearTimeout(id);
  }, [blocked, delayMs]);

  return entered;
}

export interface LeaveTransition<T> {
  /** What to render right now — the outgoing value until it has finished leaving. */
  readonly shown: T;
  /** True while `shown` is on its way out; drive the exit styling from this. */
  readonly leaving: boolean;
}

/**
 * Hold the previous value on screen long enough for it to leave.
 *
 * React's default is to unmount the old surface the instant state changes, which is why a report
 * swap used to blink: there is nothing left to animate. This defers the swap by one exit, so the
 * outgoing content is still mounted (and marked `leaving`) while it fades, and only then is
 * replaced.
 *
 * Deliberately NOT a crossfade. Two documents visible at once read as two voices; sequential reads
 * as one changing its mind — and the incoming surface types itself in, which cannot start until
 * the space is actually free.
 *
 * Closing to nothing is a leave like any other, so `null` gets its full exit rather than vanishing.
 */
export function useLeaveTransition<T>(
  value: T,
  exitMs: number = CENTER_EXIT_MS
): LeaveTransition<T> {
  const [shown, setShown] = useState<T>(value);
  const [leaving, setLeaving] = useState(false);
  // Kept in a ref so the effect can compare without listing `shown` as a dependency — doing that
  // re-runs the effect on the swap it just performed and restarts the timer forever.
  const shownRef = useRef(shown);
  shownRef.current = shown;

  useEffect(() => {
    if (Object.is(value, shownRef.current)) {
      setLeaving(false);
      return;
    }
    // Opening is immediate: there is nothing on screen to leave, and deferring it would make every
    // surface take an exit's worth of time to appear. Only a handover or a close waits.
    if (shownRef.current == null) {
      setShown(value);
      setLeaving(false);
      return;
    }
    setLeaving(true);
    const id = window.setTimeout(() => {
      setShown(value);
      setLeaving(false);
    }, exitMs);
    return () => window.clearTimeout(id);
  }, [value, exitMs]);

  return { shown, leaving };
}

export default useLeaveTransition;
