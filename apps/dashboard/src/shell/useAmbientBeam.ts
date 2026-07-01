import { useEffect, type RefObject } from "react";

/**
 * Ambient "flashlight" beams: drive the shared `--beam-x/--beam-y` and `--beam2-x/--beam2-y` CSS
 * variables that the panel outline reflections read (see shell.css). TWO beams run independently —
 * each pass enters from a RANDOM direction and offset, sweeps across the viewport at a steady speed,
 * then waits a RANDOM 0.5–2s (fully dark, off-screen) before its next pass. Because the two loops are
 * unsynced, at any moment there may be 0, 1, or 2 beams on screen.
 *
 * Pure decoration and non-interactive; it sets only CSS custom properties, never React state, and is
 * disabled under `prefers-reduced-motion` (the outlines simply keep their faint static line).
 */
const SPEED_PX_PER_S = 250;
const MIN_PAUSE_MS = 500;
const MAX_PAUSE_MS = 2000;

function randomPause(): number {
  return MIN_PAUSE_MS + Math.random() * (MAX_PAUSE_MS - MIN_PAUSE_MS);
}

/** Run one independent beam loop writing the given CSS vars; returns a cleanup. */
function runBeam(root: HTMLElement, xVar: string, yVar: string, initialDelay: number): () => void {
  let raf = 0;
  let timer = 0;
  let cancelled = false;

  function pass(): void {
    const w = window.innerWidth;
    const h = window.innerHeight;
    const cx = w / 2;
    const cy = h / 2;
    // Random sweep direction + a random perpendicular offset (so it need not cross the center).
    const theta = Math.random() * Math.PI * 2;
    const dx = Math.cos(theta);
    const dy = Math.sin(theta);
    const off = (Math.random() * 2 - 1) * Math.min(w, h) * 0.4;
    const ox = -dy * off;
    const oy = dx * off;
    const span = Math.hypot(w, h) / 2 + 700; // start/end fully off-screen either side
    const sx = cx + ox - dx * span;
    const sy = cy + oy - dy * span;
    const ex = cx + ox + dx * span;
    const ey = cy + oy + dy * span;
    const duration = (Math.hypot(ex - sx, ey - sy) / SPEED_PX_PER_S) * 1000;
    const start = performance.now();

    function frame(now: number): void {
      if (cancelled) {
        return;
      }
      const t = Math.min(1, (now - start) / duration);
      root.style.setProperty(xVar, `${sx + (ex - sx) * t}px`);
      root.style.setProperty(yVar, `${sy + (ey - sy) * t}px`);
      if (t < 1) {
        raf = requestAnimationFrame(frame);
      } else {
        timer = window.setTimeout(pass, randomPause());
      }
    }

    raf = requestAnimationFrame(frame);
  }

  timer = window.setTimeout(pass, initialDelay);

  return () => {
    cancelled = true;
    cancelAnimationFrame(raf);
    window.clearTimeout(timer);
  };
}

export function useAmbientBeam(ref: RefObject<HTMLElement | null>): void {
  useEffect(() => {
    const root = ref.current;
    if (!root || typeof requestAnimationFrame !== "function") {
      return;
    }
    if (window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches) {
      return;
    }

    // Two independent beams; the second starts after a short random offset so they don't mirror.
    const cleanups = [
      runBeam(root, "--beam-x", "--beam-y", 0),
      runBeam(root, "--beam2-x", "--beam2-y", randomPause())
    ];

    return () => cleanups.forEach((cleanup) => cleanup());
  }, [ref]);
}
