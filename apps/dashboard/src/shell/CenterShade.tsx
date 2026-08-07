import { useEffect, useRef, type RefObject } from "react";

/** Which panel corner the shade is anchored into. Report takes the top-left, Input the
 *  bottom-right — mirrored, so the two centre surfaces read as one idea facing each other. */
export type ShadeSide = "report" | "input";

/**
 * The union of the rendered LINE BOXES, not the element's border box.
 *
 * A block is as wide as its column however little is in it, so measuring the element would return
 * a constant and the shade would never appear to grow sideways. A range over the contents returns
 * the widest line and the last line, which is what the shade should actually be hugging.
 */
function textBounds(node: HTMLElement): DOMRect | null {
  const range = document.createRange();
  range.selectNodeContents(node);
  // jsdom implements Range without layout, so this method is simply absent there. A shade with
  // nothing to measure holds its last extent rather than throwing — the surface still renders,
  // which is what the region's tests are asserting.
  if (typeof range.getBoundingClientRect !== "function") {
    return null;
  }
  const box = range.getBoundingClientRect();
  return box.width || box.height ? box : null;
}

/**
 * The wash a centre surface sits in (design reference Plate 02): the panel's own colour running
 * fully into two edges and dissolving on the other two, under text that carries its own halo.
 *
 * Rendered as a child of `.heimlich` rather than of the surface it backs — that is what lets it
 * reach the panel's real edges, where the panel's own clip ends it at a border that already
 * exists. Inside the surface it would stop in open space, and a shade you can see the end of is
 * the thing this replaced.
 *
 * Its extent follows the CONTENT, re-measured whenever the content changes size or scrolls. A
 * fixed region reads as shading when text fills it and as a dark blob when it does not, and report
 * length varies enormously — so there is no correct constant to pick.
 */
export function CenterShade({
  side,
  open,
  contentRef
}: {
  side: ShadeSide;
  /** Fades the shade in and out with its surface, so the space darkens as something arrives. */
  open: boolean;
  /** The element whose text the shade should hug. */
  contentRef: RefObject<HTMLElement | null>;
}) {
  const shadeRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const shade = shadeRef.current;
    const content = contentRef.current;
    if (!shade) {
      return;
    }
    // Closed: back to a small corner, so the next open expands outward again rather than snapping
    // in at whatever size the last document happened to be.
    if (!open || !content) {
      shade.style.setProperty("--ch-shade-x", "8%");
      shade.style.setProperty("--ch-shade-y", "8%");
      return;
    }

    const panel = shade.parentElement;
    if (!panel) {
      return;
    }

    const pad = Number.parseFloat(
      getComputedStyle(shade).getPropertyValue("--ch-shade-pad") || "2.5"
    );

    const measure = () => {
      const box = textBounds(content);
      if (!box) {
        return;
      }
      const frame = panel.getBoundingClientRect();
      if (!frame.width || !frame.height) {
        return;
      }
      // Report measures out from the top-left; Input measures in from the bottom-right, because
      // its mask runs the other way.
      const x =
        side === "report"
          ? ((box.right - frame.left) / frame.width) * 100
          : ((frame.right - box.left) / frame.width) * 100;
      const y =
        side === "report"
          ? ((box.bottom - frame.top) / frame.height) * 100
          : ((frame.bottom - box.top) / frame.height) * 100;
      // Capped below 100 so a document taller than the panel still leaves the fade somewhere to
      // happen — at exactly 100% the dissolve would start off-screen and the shade would end on a
      // hard edge at the panel border, which is the failure this whole treatment exists to avoid.
      shade.style.setProperty("--ch-shade-x", `${Math.min(92, Math.max(0, x) + pad).toFixed(1)}%`);
      shade.style.setProperty("--ch-shade-y", `${Math.min(92, Math.max(0, y) + pad).toFixed(1)}%`);
    };

    measure();

    // Content grows as a report is written and moves as it is scrolled; the shade has to follow
    // both or it stops hugging the text the moment either happens. Guarded rather than assumed —
    // jsdom has no ResizeObserver, and a missing observer should cost the shade its liveness, not
    // take the whole region down with it.
    const observer =
      typeof ResizeObserver === "function" ? new ResizeObserver(measure) : null;
    observer?.observe(content);
    observer?.observe(panel);
    const scroller = content.closest(".report-region__scroll, .input-region__scroll");
    scroller?.addEventListener("scroll", measure, { passive: true });
    window.addEventListener("resize", measure);

    return () => {
      observer?.disconnect();
      scroller?.removeEventListener("scroll", measure);
      window.removeEventListener("resize", measure);
    };
  }, [side, open, contentRef]);

  return (
    <div
      ref={shadeRef}
      className="center-shade"
      data-side={side}
      data-on={open || undefined}
      aria-hidden="true"
    />
  );
}

export default CenterShade;
