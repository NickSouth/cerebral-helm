import { useEffect, type RefObject } from "react";

/**
 * Ambient "flashlight" beams: sweep two independent light passes across the viewport and
 * reflect them off every outlined surface's BeamOverlay ring (see shell.css). Each pass enters
 * from a RANDOM direction and offset, sweeps across at a steady speed, then waits a random
 * 0.5–2s (fully dark, off-screen) before its next pass. Because the two loops are unsynced, at
 * any moment there may be 0, 1, or 2 beams on screen.
 *
 * Motion is `transform: translate3d(...)` written directly on each overlay's light tile —
 * the viewport-space beam center minus the surface's viewport offset (cached per pass), so
 * every surface shows its slice of the SAME beam in one coordinated sweep. Transforms move on
 * the compositor without repainting; the previous implementation (shared `--beam-*` CSS vars +
 * `background-attachment: fixed` + per-frame `background-position`) re-rastered every masked
 * outline overlay on every frame and grew the web process by tens of MB/s to multiple GB
 * (NIC-122). Do not reintroduce per-frame paint-affecting style changes here.
 *
 * Pure decoration and non-interactive; never touches React state, and is disabled under
 * `prefers-reduced-motion` (the outlines simply keep their faint static line).
 */
const SPEED_PX_PER_S = 250;
const MIN_PAUSE_MS = 500;
const MAX_PAUSE_MS = 2000;
/** Half the 1050px light tile (see .beam-overlay__light) — offsetting by it centers the tile. */
const TILE_HALF_PX = 525;

function randomPause(): number {
  return MIN_PAUSE_MS + Math.random() * (MAX_PAUSE_MS - MIN_PAUSE_MS);
}

interface LightTarget {
  readonly el: HTMLElement;
  /** The owning surface's viewport offset — subtracted to convert beam → tile coordinates. */
  readonly ox: number;
  readonly oy: number;
}

/** One beam's light tiles across all mounted overlays, with current surface offsets. */
function collectTargets(root: HTMLElement, beam: string): LightTarget[] {
  const lights = root.querySelectorAll<HTMLElement>(`.beam-overlay__light[data-beam="${beam}"]`);
  return Array.from(lights, (el) => {
    const rect = (el.parentElement ?? el).getBoundingClientRect();
    return { el, ox: rect.left, oy: rect.top };
  });
}

/** Run one independent beam loop moving the given beam's tiles; returns a cleanup. */
function runBeam(root: HTMLElement, beam: string, initialDelay: number): () => void {
  let raf = 0;
  let timer = 0;
  let cancelled = false;
  let targets: LightTarget[] = [];

  // Surfaces move only when the viewport changes (the dashboard never scrolls): refresh the
  // cached offsets on resize, plus at every pass start — which also adopts newly mounted panels.
  const refresh = (): void => {
    targets = collectTargets(root, beam);
  };
  window.addEventListener("resize", refresh);

  function pass(): void {
    refresh();
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
      const x = sx + (ex - sx) * t;
      const y = sy + (ey - sy) * t;
      for (const target of targets) {
        target.el.style.transform = `translate3d(${x - target.ox - TILE_HALF_PX}px, ${y - target.oy - TILE_HALF_PX}px, 0)`;
      }
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
    window.removeEventListener("resize", refresh);
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
    const cleanups = [runBeam(root, "a", 0), runBeam(root, "b", randomPause())];

    return () => cleanups.forEach((cleanup) => cleanup());
  }, [ref]);
}
