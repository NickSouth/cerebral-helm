import { useEffect, type RefObject } from "react";

/**
 * Report where this surface's glass is, so the native shell can put a **real blur** behind each
 * piece of it.
 *
 * ## Why this channel has to exist
 *
 * CSS cannot blur the desktop. Inside a transparent WKWebView, `backdrop-filter` samples the page's
 * own backdrop — which, on a surface built to be seen through, is empty. Blurring what is behind
 * the *window* belongs to the window server, and the only way to ask for it is an
 * `NSVisualEffectView`.
 *
 * But an effect view blurs its whole frame, and a window-level one blurs the whole window — which
 * is precisely the "absurd region of blur" that made these surfaces read as dark slabs. The blur
 * has to be shaped to the panes and boxes, and their geometry lives here, in the layer that lays
 * them out. So the web layer measures and the native layer renders: one effect view per rect,
 * positioned behind the transparent web content.
 *
 * ## What is measured
 *
 * Whatever `selector` matches, in viewport coordinates (CSS px, y-down from the top-left), plus each
 * element's corner radius so the blur is clipped to the same shape the CSS draws. The webview fills
 * its window, so these convert to window coordinates with a single flip on the native side.
 *
 * Deliberately event-driven, never polled: a surface like the sidebar is pre-warmed at launch and
 * stays loaded for the life of the app, so a `requestAnimationFrame` loop would burn a core
 * forever for a column nobody is looking at (the lesson of NIC-122). Every source of movement is
 * observed instead — the elements resizing, the surface resizing, the list scrolling, and content
 * being added or removed — and all of them coalesce into one measurement per frame.
 */

export interface GlassRect {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
  readonly radius: number;
}

interface GlassControlWindow extends Window {
  webkit?: { messageHandlers?: { glassControl?: { postMessage(message: unknown): void } } };
}

function post(rects: readonly GlassRect[]): boolean {
  const handler = (window as GlassControlWindow).webkit?.messageHandlers?.glassControl;
  if (!handler) {
    return false;
  }
  handler.postMessage({ rects });
  return true;
}

function measure(root: HTMLElement, selector: string): GlassRect[] {
  const rects: GlassRect[] = [];
  for (const element of root.querySelectorAll<HTMLElement>(selector)) {
    const box = element.getBoundingClientRect();
    // A zero-area element is either display:none or not laid out yet; blurring it would leave a
    // stray view parked at the origin.
    if (box.width < 1 || box.height < 1) {
      continue;
    }
    const radius = Number.parseFloat(getComputedStyle(element).borderTopLeftRadius) || 0;
    rects.push({
      x: Math.round(box.left),
      y: Math.round(box.top),
      width: Math.round(box.width),
      height: Math.round(box.height),
      // A radius cannot exceed half the shorter side; CSS clamps it, and passing an unclamped
      // value to a layer would round the whole thing into a lozenge.
      radius: Math.min(radius, box.width / 2, box.height / 2)
    });
  }
  return rects;
}

export function useGlassGeometry(
  rootRef: RefObject<HTMLElement | null>,
  selector: string
): void {
  useEffect(() => {
    const root = rootRef.current;
    // No native channel in a plain browser preview: nothing to report to, and no cost paid.
    if (!root || !(window as GlassControlWindow).webkit?.messageHandlers?.glassControl) {
      return;
    }

    let frame = 0;
    let last = "";

    const publish = () => {
      frame = 0;
      const rects = measure(root, selector);
      // Diff before posting. Scrolling fires far more often than the geometry actually changes, and
      // every message costs a hop plus native view work.
      const encoded = JSON.stringify(rects);
      if (encoded === last) {
        return;
      }
      last = encoded;
      post(rects);
    };

    const schedule = () => {
      if (frame === 0) {
        frame = requestAnimationFrame(publish);
      }
    };

    const resizeObserver = new ResizeObserver(schedule);
    resizeObserver.observe(root);
    for (const element of root.querySelectorAll<HTMLElement>(selector)) {
      resizeObserver.observe(element);
    }

    // Elements appearing or disappearing changes both the set and everything below it, and it is
    // also when new elements need observing — so re-observe from scratch on any structural change.
    const mutationObserver = new MutationObserver(() => {
      resizeObserver.disconnect();
      resizeObserver.observe(root);
      for (const element of root.querySelectorAll<HTMLElement>(selector)) {
        resizeObserver.observe(element);
      }
      schedule();
    });
    mutationObserver.observe(root, { childList: true, subtree: true });

    // Capture phase: scrolling happens on inner containers, and scroll does not bubble.
    root.addEventListener("scroll", schedule, { capture: true, passive: true });
    window.addEventListener("resize", schedule);

    schedule();

    return () => {
      if (frame !== 0) {
        cancelAnimationFrame(frame);
      }
      resizeObserver.disconnect();
      mutationObserver.disconnect();
      root.removeEventListener("scroll", schedule, { capture: true });
      window.removeEventListener("resize", schedule);
      // Leave nothing blurred behind a surface that is going away.
      post([]);
    };
  }, [rootRef, selector]);
}

export default useGlassGeometry;
