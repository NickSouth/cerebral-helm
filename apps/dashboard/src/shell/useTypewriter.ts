import { useEffect, type RefObject } from "react";

/** Reveal rate. Fast enough that a long brief does not become a waiting game, slow enough to read
 *  as writing rather than as a render glitch. */
const CHARS_PER_SECOND = 62;
/** The beat between one text run and the next — what makes it read as composed lines rather than
 *  one undifferentiated stream of characters. */
const RUN_PAUSE_MS = 120;
/** How close to the bottom counts as "following along". Past this the reader has scrolled up
 *  deliberately and must not be yanked back. */
const FOLLOW_SLOP_PX = 48;

interface Run {
  readonly node: Text;
  readonly text: string;
  readonly start: number;
  readonly end: number;
}

/**
 * Every text node under `root`, in document order, with its offset into the combined text.
 *
 * Walking the rendered DOM rather than the source data is what makes this work for **every** block
 * kind — metrics, checklists, scoreboards, and anything added later — with the block renderer
 * untouched. A typewriter that understood report blocks would need extending every time one is.
 */
function collectRuns(root: HTMLElement): { runs: Run[]; total: number } {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  const runs: Run[] = [];
  let total = 0;
  while (walker.nextNode()) {
    const node = walker.currentNode as Text;
    const text = node.data;
    if (!text) {
      continue;
    }
    runs.push({ node, text, start: total, end: total + text.length });
    total += text.length;
  }
  return { runs, total };
}

/**
 * Type a rendered subtree in, character by character, the way a model writes it.
 *
 * Only text node *contents* are touched — never structure — so React keeps ownership of the tree
 * and this cannot desynchronise it. If React re-renders mid-run the worst case is the full text
 * appearing at once, which is the same state the animation was heading for anyway.
 *
 * Restores the complete text on cleanup, so an unmount or a document change never strands a report
 * half-written. Skipped entirely when motion is reduced: the text is simply there, which is the
 * honest equivalent of "typed instantly" and avoids animating a surface someone asked to hold
 * still.
 */
export function useTypewriter(
  rootRef: RefObject<HTMLElement | null>,
  /** Changing this restarts the run — use whatever identifies the document. */
  key: string | null,
  {
    enabled = true,
    caretRef
  }: { enabled?: boolean; caretRef?: RefObject<HTMLElement | null> } = {}
): void {
  useEffect(() => {
    const root = rootRef.current;
    if (!root || key === null || !enabled) {
      return;
    }

    const { runs, total } = collectRuns(root);
    if (!total) {
      return;
    }

    const caret = caretRef?.current ?? null;
    const scroller = root.closest<HTMLElement>(
      ".report-region__scroll, .input-region__scroll"
    );

    const restore = () => {
      for (const run of runs) {
        run.node.data = run.text;
      }
      root.removeAttribute("aria-busy");
      caret?.removeAttribute("data-on");
    };

    let shown = 0;
    let runIndex = 0;
    let pauseUntil = 0;
    let last = 0;
    let raf = 0;
    let started = false;

    /**
     * Hiding the text happens on the FIRST FRAME, not here.
     *
     * If it happened up front, then anywhere `requestAnimationFrame` never runs — a hidden tab, a
     * detached render, a test environment — the report would be blanked and stay blanked. Deferring
     * it means the failure mode is "the text is simply there", which is the same graceful end state
     * as reduced motion rather than an empty surface.
     */
    const begin = (now: number) => {
      started = true;
      last = now;
      for (const run of runs) {
        run.node.data = "";
      }
      // The document is being written; a screen reader should be told rather than read a text that
      // keeps changing under it.
      root.setAttribute("aria-busy", "true");
      caret?.setAttribute("data-on", "");
    };

    /** Park the caret at the reveal point using a collapsed range — no extra DOM, and it lands
     *  wherever the text actually wrapped to. */
    const placeCaret = (charsShown: number) => {
      if (!caret) {
        return;
      }
      const run = runs.find((candidate) => charsShown <= candidate.end) ?? runs[runs.length - 1];
      const offset = Math.max(0, Math.min(run.text.length, charsShown - run.start));
      const range = document.createRange();
      if (typeof range.getBoundingClientRect !== "function") {
        return;
      }
      range.setStart(run.node, Math.min(offset, run.node.data.length));
      range.collapse(true);
      const point = range.getBoundingClientRect();
      const base = root.getBoundingClientRect();
      if (!point.height && !point.width) {
        return;
      }
      caret.style.transform = `translate(${(point.left - base.left).toFixed(1)}px, ${(
        point.top - base.top
      ).toFixed(1)}px)`;
      caret.style.height = `${point.height.toFixed(1)}px`;
    };

    const frame = (now: number) => {
      if (!started) {
        begin(now);
        raf = requestAnimationFrame(frame);
        return;
      }
      const delta = now - last;
      last = now;
      if (now >= pauseUntil) {
        shown = Math.min(total, shown + (delta * CHARS_PER_SECOND) / 1000);
      }
      const chars = Math.floor(shown);

      for (const run of runs) {
        const want = Math.max(0, Math.min(run.text.length, chars - run.start));
        if (run.node.data.length !== want) {
          run.node.data = run.text.slice(0, want);
        }
      }

      // A completed run earns a beat before the next one starts.
      while (runIndex < runs.length && chars >= runs[runIndex].end) {
        runIndex += 1;
        pauseUntil = now + RUN_PAUSE_MS;
      }

      placeCaret(chars);

      // Follow the writing down, but only while the reader is already at the bottom — scrolling up
      // mid-report is a deliberate act and yanking them back would fight them.
      if (scroller) {
        const distance = scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight;
        if (distance <= FOLLOW_SLOP_PX) {
          scroller.scrollTop = scroller.scrollHeight;
        }
      }

      if (chars < total) {
        raf = requestAnimationFrame(frame);
      } else {
        restore();
      }
    };

    raf = requestAnimationFrame(frame);

    return () => {
      cancelAnimationFrame(raf);
      // Only undo what was actually done — restoring before the run began would strip `aria-busy`
      // and the caret flag off a surface that never had them.
      if (started) {
        restore();
      }
    };
  }, [rootRef, key, enabled, caretRef]);
}

export default useTypewriter;
