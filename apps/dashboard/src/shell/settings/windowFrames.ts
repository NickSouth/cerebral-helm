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
  centered: { x: 0.125, y: 0.125, w: 0.75, h: 0.75 }
};

/** Declaration order must match the backend `WindowFrame` enum so ties break the same
 *  way (`WindowFrameGeometry.snap` breaks ties by enum order). */
const FRAME_ORDER: readonly LayoutFrame[] = [
  "full",
  "left-half",
  "right-half",
  "top-half",
  "bottom-half",
  "left-two-thirds",
  "right-third",
  "centered"
];

function intersectionOverUnion(a: FrameRect, b: FrameRect): number {
  const ix = Math.max(a.x, b.x);
  const iy = Math.max(a.y, b.y);
  const iMaxX = Math.min(a.x + a.w, b.x + b.w);
  const iMaxY = Math.min(a.y + a.h, b.y + b.h);
  const iw = iMaxX - ix;
  const ih = iMaxY - iy;
  if (iw <= 0 || ih <= 0) {
    return 0;
  }
  const intersection = iw * ih;
  const union = a.w * a.h + b.w * b.h - intersection;
  return union > 0 ? intersection / union : 0;
}

/** The named frame a free rect most closely occupies, by intersection-over-union —
 *  the frontend mirror of `WindowFrameGeometry.snap` (same tie-break order). */
export function snapToFrame(rect: FrameRect): LayoutFrame {
  let best: LayoutFrame = "full";
  let bestScore = -1;
  for (const frame of FRAME_ORDER) {
    const score = intersectionOverUnion(rect, FRAME_RECTS[frame]);
    if (score > bestScore) {
      bestScore = score;
      best = frame;
    }
  }
  return best;
}
