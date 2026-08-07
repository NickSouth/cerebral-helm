import { useRef, useState, type PointerEvent as ReactPointerEvent } from "react";
import type { LayoutFrame } from "../../bridge/cerebralBridge";
import { humanizeId } from "../labels";
import { FRAME_RECTS, snapToFrame, type FrameRect } from "./windowFrames";

/** One rectangle on the canvas: a static window or the (single) hotswap slot. */
export interface CanvasItem {
  readonly id: string;
  readonly label: string;
  readonly frame: LayoutFrame;
  readonly hotswap?: boolean;
}

interface DragState {
  readonly id: string;
  readonly rect: FrameRect;
}

const MIN_SIZE = 0.1;

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

function clampMove(rect: FrameRect): FrameRect {
  return { ...rect, x: clamp(rect.x, 0, 1 - rect.w), y: clamp(rect.y, 0, 1 - rect.h) };
}

/** The 4 resize corners (`n`/`s` = top/bottom edge, `w`/`e` = left/right edge). */
type Corner = "nw" | "ne" | "sw" | "se";

/** Resize by dragging one corner, keeping the opposite corner fixed and clamping each
 *  moved edge inside the board with a sensible minimum size. */
function resizeRect(start: FrameRect, dx: number, dy: number, corner: Corner): FrameRect {
  let { x, y, w, h } = start;
  if (corner.includes("w")) {
    const nx = clamp(x + dx, 0, x + w - MIN_SIZE);
    w += x - nx;
    x = nx;
  } else {
    w = clamp(w + dx, MIN_SIZE, 1 - x);
  }
  if (corner.includes("n")) {
    const ny = clamp(y + dy, 0, y + h - MIN_SIZE);
    h += y - ny;
    y = ny;
  } else {
    h = clamp(h + dy, MIN_SIZE, 1 - y);
  }
  return { x, y, w, h };
}

const CORNERS: readonly Corner[] = ["nw", "ne", "sw", "se"];

/**
 * The layout authoring canvas (NIC-142): a proportional view of the chosen display with
 * one rectangle per window plus the hotswap slot. Drag a rectangle to move it or its
 * corner handle to resize; on release the free rect snaps to the nearest of the 8 named
 * frames (the same intersection-over-union rule the AX capture path uses), so the stored
 * layout is always a reliable named frame. The hotswap slot is accent-highlighted; a ×
 * removes an item.
 */
export function LayoutCanvas({
  items,
  onChangeFrame,
  onRemove
}: {
  items: readonly CanvasItem[];
  onChangeFrame: (id: string, frame: LayoutFrame) => void;
  onRemove: (id: string) => void;
}) {
  const boardRef = useRef<HTMLDivElement>(null);
  const [drag, setDrag] = useState<DragState | null>(null);
  // The live drag mirrored in a ref so pointerup reads the final rect and calls
  // `onChangeFrame` from the plain event handler — never from inside a state updater.
  const dragRef = useRef<DragState | null>(null);
  const startRef = useRef<{ px: number; py: number; rect: FrameRect } | null>(null);

  const beginDrag =
    (id: string, frame: LayoutFrame, mode: "move" | Corner) =>
    (event: ReactPointerEvent<HTMLElement>) => {
      event.preventDefault();
      event.stopPropagation();
      const board = boardRef.current;
      if (!board) {
        return;
      }
      const bounds = board.getBoundingClientRect();
      const startRect = FRAME_RECTS[frame];
      startRef.current = { px: event.clientX, py: event.clientY, rect: startRect };
      const initial: DragState = { id, rect: startRect };
      dragRef.current = initial;
      setDrag(initial);

      const onMove = (moveEvent: PointerEvent) => {
        const start = startRef.current;
        if (!start || bounds.width === 0 || bounds.height === 0) {
          return;
        }
        const dx = (moveEvent.clientX - start.px) / bounds.width;
        const dy = (moveEvent.clientY - start.py) / bounds.height;
        const next =
          mode === "move"
            ? clampMove({ ...start.rect, x: start.rect.x + dx, y: start.rect.y + dy })
            : resizeRect(start.rect, dx, dy, mode);
        const updated: DragState = { id, rect: next };
        dragRef.current = updated;
        setDrag(updated);
      };
      const onUp = () => {
        window.removeEventListener("pointermove", onMove);
        window.removeEventListener("pointerup", onUp);
        const finished = dragRef.current;
        dragRef.current = null;
        startRef.current = null;
        setDrag(null);
        if (finished) {
          onChangeFrame(finished.id, snapToFrame(finished.rect));
        }
      };
      window.addEventListener("pointermove", onMove);
      window.addEventListener("pointerup", onUp);
    };

  return (
    <div className="layout-canvas" ref={boardRef} role="group" aria-label="Layout canvas">
      {items.map((item) => {
        const rect = drag && drag.id === item.id ? drag.rect : FRAME_RECTS[item.frame];
        return (
          <div
            key={item.id}
            className="layout-canvas__win"
            data-hotswap={item.hotswap ? "true" : undefined}
            data-dragging={drag?.id === item.id ? "true" : undefined}
            style={{
              left: `${rect.x * 100}%`,
              top: `${rect.y * 100}%`,
              width: `${rect.w * 100}%`,
              height: `${rect.h * 100}%`
            }}
            onPointerDown={beginDrag(item.id, item.frame, "move")}
          >
            <span className="layout-canvas__win-label">{item.label}</span>
            <span className="layout-canvas__win-frame">{humanizeId(item.frame)}</span>
            <button
              type="button"
              className="layout-canvas__remove"
              aria-label={`Remove ${item.label}`}
              title="Remove"
              onPointerDown={(event) => event.stopPropagation()}
              onClick={() => onRemove(item.id)}
            >
              ×
            </button>
            {CORNERS.map((corner) => (
              <span
                key={corner}
                className="layout-canvas__handle"
                data-corner={corner}
                aria-hidden="true"
                onPointerDown={beginDrag(item.id, item.frame, corner)}
              />
            ))}
          </div>
        );
      })}
    </div>
  );
}

export default LayoutCanvas;
