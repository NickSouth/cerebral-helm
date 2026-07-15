import type { LayoutFrame } from "../../bridge/cerebralBridge";

/** A rectangle in display-fraction space (0..1 on each axis). */
export interface FrameRect {
  readonly x: number;
  readonly y: number;
  readonly w: number;
  readonly h: number;
}

/**
 * The rect each named frame occupies within a display's visible area (NIC-142) — the
 * frontend mirror of `WindowFrameGeometry.resolve`, in 0..1 fractions so the editor
 * canvas draws exactly where the AX adapter will place the window.
 */
export const FRAME_RECTS: Readonly<Record<LayoutFrame, FrameRect>> = {
  full: { x: 0, y: 0, w: 1, h: 1 },
  "left-half": { x: 0, y: 0, w: 0.5, h: 1 },
  "right-half": { x: 0.5, y: 0, w: 0.5, h: 1 },
  "top-half": { x: 0, y: 0, w: 1, h: 0.5 },
  "bottom-half": { x: 0, y: 0.5, w: 1, h: 0.5 },
  "left-two-thirds": { x: 0, y: 0, w: 2 / 3, h: 1 },
  "right-third": { x: 2 / 3, y: 0, w: 1 / 3, h: 1 },
  "left-third": { x: 0, y: 0, w: 1 / 3, h: 1 },
  "right-two-thirds": { x: 1 / 3, y: 0, w: 2 / 3, h: 1 },
  centered: { x: 0.125, y: 0.125, w: 0.75, h: 0.75 }
};

/** Declaration order (ties break toward the earlier frame). */
const FRAME_ORDER: readonly LayoutFrame[] = [
  "full",
  "left-half",
  "right-half",
  "top-half",
  "bottom-half",
  "left-two-thirds",
  "right-third",
  "left-third",
  "right-two-thirds",
  "centered"
];

/** Sum of absolute differences of the four edges (left, top, right, bottom). */
function edgeDistance(a: FrameRect, b: FrameRect): number {
  return (
    Math.abs(a.x - b.x) +
    Math.abs(a.y - b.y) +
    Math.abs(a.x + a.w - (b.x + b.w)) +
    Math.abs(a.y + a.h - (b.y + b.h))
  );
}

/**
 * The named frame a dragged/resized rect snaps to, by nearest edges (NIC-142). Edge
 * distance — not intersection-over-union — so a thin frame like right-third is just as
 * reachable as a big one: IoU is dominated by area, which makes a narrow target
 * (little overlap) nearly impossible to hit, whereas matching the four edges treats
 * every frame equally. The canvas only needs to get *close* to a frame's edges for it
 * to win.
 */
export function snapToFrame(rect: FrameRect): LayoutFrame {
  let best: LayoutFrame = "full";
  let bestScore = Infinity;
  for (const frame of FRAME_ORDER) {
    const score = edgeDistance(rect, FRAME_RECTS[frame]);
    if (score < bestScore) {
      bestScore = score;
      best = frame;
    }
  }
  return best;
}
