import { useEffect, type RefObject } from "react";

/** The unhurried rate, and the one a SHORT document keeps: fast enough not to be a waiting game,
 *  slow enough to read as writing rather than as a render glitch. Only a document too long to fit
 *  the budget below at this rate types faster. */
const BASE_CHARS_PER_SECOND = 62;
/**
 * What the whole run is allowed to take, near enough.
 *
 * A brief is not a short story: at a fixed rate a long one takes tens of seconds, and the reader
 * either waits or scrolls past the animation, which makes it a cost rather than a quality. So
 * length buys speed — the rate rises to fit the document into this budget, and a long report reads
 * as a fast sweep down the page instead of a crawl. Short documents never take the full budget;
 * they simply finish sooner at the base rate.
 */
const TARGET_DURATION_MS = 1000;
/** The beat between one text run and the next — what makes it read as composed lines rather than
 *  one undifferentiated stream of characters. Shrinks with the run count, see below. */
const BASE_RUN_PAUSE_MS = 120;
/** The share of the budget the beats may spend. A forty-block report at the full beat would pause
 *  for nearly five seconds before a single character was written, so the beat is divided across
 *  however many runs there are and the writing keeps the rest. */
const PAUSE_BUDGET_SHARE = 0.25;
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
 * A painted element, with the character position it sits at.
 *
 * These are the parts of a report that carry no text of their own — a calendar event's colour dot,
 * a scoreboard's team accent, a proposal's pill border. They are invisible to a text walk, so
 * before this they all appeared on the first frame: the reader saw a column of coloured dots and
 * empty pills, then watched the words arrive around them. Every element is timed, not just the
 * empty ones, because a box drawn around text is the same bug — the pill must arrive with its
 * label, not ahead of it.
 */
interface Ornament {
  readonly element: HTMLElement;
  /** The offset of the first character AT OR AFTER this element opens. Revealing at `chars > at`
   *  puts the paint and its first character on the same frame. */
  readonly at: number;
}

/**
 * Every text node under `root`, in document order, with its offset into the combined text — plus
 * every element, tagged with the offset it opens at.
 *
 * Walking the rendered DOM rather than the source data is what makes this work for **every** block
 * kind — metrics, checklists, scoreboards, and anything added later — with the block renderer
 * untouched. A typewriter that understood report blocks would need extending every time one is.
 */
function collectTimeline(
  root: HTMLElement,
  exclude: Element | null
): { runs: Run[]; ornaments: Ornament[]; total: number } {
  const walker = document.createTreeWalker(
    root,
    NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT
  );
  const runs: Run[] = [];
  const ornaments: Ornament[] = [];
  let total = 0;
  while (walker.nextNode()) {
    const node = walker.currentNode;
    if (node.nodeType === Node.ELEMENT_NODE) {
      const element = node as HTMLElement;
      // The caret is the hook's own instrument, not part of the document. It is also driven by
      // `display`, so hiding it here would fight the rule that shows it.
      if (element === exclude || exclude?.contains(element)) {
        continue;
      }
      ornaments.push({ element, at: total });
      continue;
    }
    const text = (node as Text).data;
    if (!text) {
      continue;
    }
    runs.push({ node: node as Text, text, start: total, end: total + text.length });
    total += text.length;
  }
  return { runs, ornaments, total };
}

/**
 * Type a rendered subtree in, character by character, the way a model writes it.
 *
 * Only text node *contents* and element `visibility` are touched — never structure — so React keeps
 * ownership of the tree and this cannot desynchronise it. `visibility` rather than `display` is
 * deliberate: hidden elements keep their geometry, so nothing reflows as the document reveals and
 * the caret's range measurements stay valid throughout. If React re-renders mid-run the worst case
 * is the full text appearing at once, which is the same state the animation was heading for anyway.
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

    const caret = caretRef?.current ?? null;
    const { runs, ornaments, total } = collectTimeline(root, caret);
    if (!total) {
      return;
    }

    // Pacing is decided per document, from its actual length, because a fixed rate cannot serve
    // both a one-line greeting and a forty-block brief. The beats are budgeted first — they are
    // the part that scales with block count rather than with characters — and the writing takes
    // whatever is left, at no less than the base rate so short documents stay unhurried.
    const gaps = Math.max(0, runs.length - 1);
    const runPauseMs = gaps
      ? Math.min(BASE_RUN_PAUSE_MS, (TARGET_DURATION_MS * PAUSE_BUDGET_SHARE) / gaps)
      : 0;
    const writingMs = Math.max(1, TARGET_DURATION_MS - runPauseMs * gaps);
    const charsPerSecond = Math.max(BASE_CHARS_PER_SECOND, (total * 1000) / writingMs);

    const scroller = root.closest<HTMLElement>(
      ".report-region__scroll, .input-region__scroll"
    );

    /**
     * What this hook last wrote into each run's node, so it can tell its own edits from React's.
     *
     * `run.text` was captured when the timeline was collected, and the DOM can move on afterwards:
     * React reuses a text node and rewrites it when a document's content changes under a STABLE
     * key — which is exactly what a model-composed report does when its body replaces the line
     * saying it was being written (NIC-228). Writing to that node afterwards, whether mid-run or on
     * restore, puts the stale capture back and DELETES the new content: the reader is left looking
     * at "Writing your brief…" with the finished brief rendered underneath it.
     *
     * A prefix test is NOT enough, and the hole is specific: blanking writes `""`, and every string
     * starts with `""`. A node this hook blanked and React then rewrote still looked like its own —
     * which is exactly the case a reader hits by looking away while a brief composes, since the run
     * pauses with everything blank while the tab is hidden and `requestAnimationFrame` stops.
     *
     * Recording the exact value written removes the ambiguity: a node holding something else has
     * been changed by React and is left alone. Deliberately NOT a check on whether the node is
     * attached — a node detached by an unmount is still this hook's to restore, because React may
     * reuse those very nodes and handing them back truncated is how a report comes back
     * half-written.
     */
    const written = new Map<Text, string>();
    const isOurs = (run: Run) => written.get(run.node) === run.node.data;

    const write = (run: Run, value: string) => {
      run.node.data = value;
      written.set(run.node, value);
    };

    const restore = () => {
      for (const run of runs) {
        if (isOurs(run)) {
          write(run, run.text);
        }
      }
      // Remove the property rather than clearing the style: these elements carry React's own
      // inline colours (an event's dot, a team's accent) and must keep them.
      for (const ornament of ornaments) {
        ornament.element.style.removeProperty("visibility");
      }
      root.removeAttribute("aria-busy");
      caret?.removeAttribute("data-on");
    };

    let shown = 0;
    let runIndex = 0;
    // Ornaments come out of a document-order walk, so their offsets only ever increase and a single
    // advancing cursor reveals them — no per-frame sweep over every element in the report.
    let ornamentIndex = 0;
    let pauseUntil = 0;
    let last = 0;
    let raf = 0;
    let started = false;

    /**
     * Hiding the document happens on the FIRST FRAME, not here.
     *
     * If it happened up front, then anywhere `requestAnimationFrame` never runs — a hidden tab, a
     * detached render, a test environment — the report would be blanked and stay blanked. Deferring
     * it means the failure mode is "the report is simply there", which is the same graceful end
     * state as reduced motion rather than an empty surface.
     */
    const begin = (now: number) => {
      started = true;
      last = now;
      for (const run of runs) {
        write(run, "");
      }
      for (const ornament of ornaments) {
        ornament.element.style.visibility = "hidden";
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
        shown = Math.min(total, shown + (delta * charsPerSecond) / 1000);
      }
      const chars = Math.floor(shown);

      for (const run of runs) {
        const want = Math.max(0, Math.min(run.text.length, chars - run.start));
        // Same rule as `restore`, and it matters here too: a body that lands while the header is
        // still being written would otherwise be overwritten a frame later.
        if (run.node.data.length !== want && isOurs(run)) {
          write(run, run.text.slice(0, want));
        }
      }

      // Paint arrives with the first character it belongs to, never before it.
      while (ornamentIndex < ornaments.length && chars > ornaments[ornamentIndex].at) {
        ornaments[ornamentIndex].element.style.removeProperty("visibility");
        ornamentIndex += 1;
      }

      // A completed run earns a beat before the next one starts.
      while (runIndex < runs.length && chars >= runs[runIndex].end) {
        runIndex += 1;
        pauseUntil = now + runPauseMs;
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
