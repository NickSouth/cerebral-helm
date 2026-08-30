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
  exclude: Element | null,
  /**
   * What a node's text really is, for nodes this hook has already truncated.
   *
   * Re-collecting mid-run cannot read `node.data`: a node the animation has blanked holds `""`, and
   * adopting that as its text would delete it from the document permanently. The caller supplies
   * what it knows and gets back what it should remember.
   */
  textOf: (node: Text) => string
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
    const text = textOf(node as Text);
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

    /**
     * What this hook last wrote into each node, and what that node's text really is.
     *
     * `written` is how it tells its own edits from React's. A prefix test is NOT enough, and the
     * hole is specific: blanking writes `""`, and every string starts with `""`, so a node this hook
     * blanked and React then rewrote still looked like its own. Recording the exact value removes
     * the ambiguity — a node holding something else has been changed by React and is left alone.
     *
     * `canonical` is what the node should say when finished, which `node.data` cannot answer once
     * the animation has truncated it.
     */
    const written = new Map<Text, string>();
    const canonical = new Map<Text, string>();

    /**
     * A node's real text: what this hook remembers if it still owns the node, otherwise whatever
     * React has put there now — which is how a line React rewrote mid-run gets adopted rather than
     * overwritten with a stale capture.
     */
    const textOf = (node: Text): string => {
      if (written.get(node) === node.data) {
        return canonical.get(node) ?? node.data;
      }
      return node.data;
    };

    let { runs, ornaments, total } = collectTimeline(root, caret, textOf);
    if (!total) {
      return;
    }

    // Pacing is decided per document, from its actual length, because a fixed rate cannot serve
    // both a one-line greeting and a forty-block brief. The beats are budgeted first — they are
    // the part that scales with block count rather than with characters — and the writing takes
    // whatever is left, at no less than the base rate so short documents stay unhurried.
    //
    // Recomputed whenever the document grows, because a streamed report is not one document: it is
    // a header, then a block, then another, and a rate fixed at the header's length would crawl
    // through everything after it.
    let runPauseMs = 0;
    let charsPerSecond = BASE_CHARS_PER_SECOND;
    /**
     * - Parameter revealed: how much is already on screen. The budget covers what is LEFT to write,
     *   not the document's whole length — otherwise a block appended to a finished report is paced
     *   as though the finished part still had to be typed, and 74 new characters against a 312
     *   character document come out at 312 a second. Measured in the browser: the append arrived
     *   faster than a quarter-second sample, which is indistinguishable from not animating at all.
     */
    const pace = (revealed = 0) => {
      const gaps = Math.max(0, runs.length - 1);
      runPauseMs = gaps
        ? Math.min(BASE_RUN_PAUSE_MS, (TARGET_DURATION_MS * PAUSE_BUDGET_SHARE) / gaps)
        : 0;
      const writingMs = Math.max(1, TARGET_DURATION_MS - runPauseMs * gaps);
      const remaining = Math.max(0, total - revealed);
      charsPerSecond = Math.max(BASE_CHARS_PER_SECOND, (remaining * 1000) / writingMs);
    };
    pace();

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
    const isOurs = (run: Run) => written.get(run.node) === run.node.data;

    const write = (run: Run, value: string) => {
      run.node.data = value;
      written.set(run.node, value);
      canonical.set(run.node, run.text);
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

    /**
     * Set when the document changes under a stable key — a streamed block landing (NIC-253).
     *
     * The alternative was re-keying the whole run, and that is exactly what must not happen: it
     * blanks the header a reader is already reading and types it again. So growth is folded into
     * the run in progress instead, keeping the position already revealed.
     */
    let needsRecollect = false;
    const observer = new MutationObserver((records) => {
      for (const record of records) {
        // This hook's own writes are not news. Without this test the observer would fire on every
        // frame it drew and re-collect forever.
        if (record.type === "characterData") {
          const node = record.target as Text;
          if (written.get(node) === node.data) continue;
        }
        needsRecollect = true;
        // A block can land after the run has finished — a streamed brief pauses between blocks, and
        // the animation reaches the end of what it has long before the model sends more. Without
        // re-arming here the loop is simply over, and everything after the first pause would appear
        // whole instead of being written.
        resume();
        return;
      }
    });
    observer.observe(root, { childList: true, subtree: true, characterData: true });

    let shown = 0;
    let runIndex = 0;
    // Ornaments come out of a document-order walk, so their offsets only ever increase and a single
    // advancing cursor reveals them — no per-frame sweep over every element in the report.
    let ornamentIndex = 0;
    let pauseUntil = 0;
    let last = 0;
    let raf = 0;
    let started = false;
    let running = false;
    /// Set when the loop restarts after finishing, so the first frame back does not treat the whole
    /// idle gap as elapsed writing time and jump to the end.
    let resetClock = false;

    const markBusy = () => {
      // The document is being written; a screen reader should be told rather than read a text that
      // keeps changing under it.
      root.setAttribute("aria-busy", "true");
      caret?.setAttribute("data-on", "");
    };

    // Declared before `frame` and referring to it: the reference is only evaluated when called,
    // and the first call is after `frame` exists.
    const schedule = () => {
      running = true;
      raf = requestAnimationFrame((now) => frame(now));
    };

    /** Wake the loop for newly arrived content, without rewinding what is already written. */
    const resume = () => {
      if (running || !started) return;
      resetClock = true;
      markBusy();
      schedule();
    };

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
      markBusy();
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
        schedule();
        return;
      }
      if (resetClock) {
        resetClock = false;
        last = now;
      }
      const delta = now - last;
      last = now;

      if (needsRecollect) {
        needsRecollect = false;
        // `shown` is deliberately NOT reset: the reader keeps everything already written, and only
        // what arrived past that point is typed. Text nodes React changed are adopted here rather
        // than fought over — `textOf` hands back their new content, so a placeholder replaced by the
        // model's own line simply becomes part of the document being written.
        const next = collectTimeline(root, caret, textOf);
        runs = next.runs;
        ornaments = next.ornaments;
        total = next.total;
        pace(shown);
        // Anything past the reveal point is hidden before it can be seen: a block that flashed in
        // whole and then rewound would read worse than one that never appeared.
        const chars = Math.floor(shown);
        for (const run of runs) {
          const want = Math.max(0, Math.min(run.text.length, chars - run.start));
          if (run.node.data.length !== want) write(run, run.text.slice(0, want));
        }
        for (const ornament of ornaments) {
          if (ornament.at >= chars) ornament.element.style.visibility = "hidden";
        }
        // Both cursors are positions in the new arrays, so they are re-derived rather than carried.
        runIndex = runs.filter((run) => chars >= run.end).length;
        ornamentIndex = ornaments.filter((ornament) => chars > ornament.at).length;
      }

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
        schedule();
      } else {
        running = false;
        restore();
      }
    };

    schedule();

    return () => {
      observer.disconnect();
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
