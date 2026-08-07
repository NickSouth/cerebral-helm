import { cleanup, render } from "@testing-library/react";
import { useRef } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { useTypewriter } from "./useTypewriter";

/**
 * The centre's writing animation. It reveals a subtree that React owns, character by character, by
 * editing text-node *contents* only — never structure — so it cannot desynchronise the tree.
 *
 * Two properties matter more than the animation itself and are what most of these cases pin:
 *
 *  * **Blanking happens on the first frame, not at effect time.** Anywhere `requestAnimationFrame`
 *    never runs — a hidden tab, a detached render, a test environment — hiding the text up front
 *    would blank the report and leave it blank forever. Deferring makes the failure mode "the text
 *    is simply there", the same graceful end state as reduced motion.
 *  * **Cleanup restores.** An unmount or a document change mid-run must never strand a report
 *    half-written.
 */

/** 50 characters, so at 62 chars/second a half-second frame is an unambiguous partial reveal. */
const FIRST = "The market opened quietly and closed the same way.";
const SECOND = "Two names carried it.";

function Host({
  docKey = "doc-1",
  enabled = true,
  withCaret = false,
  paragraphs = [FIRST]
}: {
  docKey?: string | null;
  enabled?: boolean;
  withCaret?: boolean;
  paragraphs?: readonly string[];
}) {
  const ref = useRef<HTMLDivElement>(null);
  const caretRef = useRef<HTMLSpanElement>(null);
  useTypewriter(ref, docKey, { enabled, caretRef: withCaret ? caretRef : undefined });
  return (
    <div ref={ref} data-testid="doc">
      {paragraphs.map((text, index) => (
        <p key={index}>{text}</p>
      ))}
      {withCaret ? <span ref={caretRef} data-testid="caret" /> : null}
    </div>
  );
}

describe("useTypewriter", () => {
  let queue: FrameRequestCallback[];
  let cancelled: number[];

  beforeEach(() => {
    queue = [];
    cancelled = [];
    vi.stubGlobal("requestAnimationFrame", (cb: FrameRequestCallback) => {
      queue.push(cb);
      return queue.length;
    });
    vi.stubGlobal("cancelAnimationFrame", (handle: number) => {
      cancelled.push(handle);
    });
  });

  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
  });

  /** Run whatever frames are pending, at `time` on the rAF clock. */
  function frame(time: number) {
    for (const cb of queue.splice(0)) cb(time);
  }

  function textOf(root: HTMLElement): string {
    return root.textContent ?? "";
  }

  it("leaves the text alone until the first frame actually runs", () => {
    const { getByTestId } = render(<Host />);
    // The effect has run and scheduled a frame, but no frame has fired.
    expect(textOf(getByTestId("doc"))).toBe(FIRST);
    expect(getByTestId("doc").getAttribute("aria-busy")).toBeNull();
  });

  it("survives an environment where frames never run", () => {
    const view = render(<Host />);
    view.unmount();
    // Nothing was hidden, so nothing needs restoring — and crucially nothing was left blank.
    expect(document.body.textContent).toBe("");
  });

  it("blanks on the first frame, then reveals and restores", () => {
    const { getByTestId } = render(<Host />);
    const doc = getByTestId("doc");

    frame(0);
    expect(textOf(doc)).toBe("");
    // A document being written is not a document a screen reader should try to follow.
    expect(doc.getAttribute("aria-busy")).toBe("true");

    // 62 chars/second, so half a second is a partial reveal of this sentence.
    frame(500);
    const partial = textOf(doc);
    expect(partial.length).toBeGreaterThan(0);
    expect(partial.length).toBeLessThan(FIRST.length);
    expect(FIRST.startsWith(partial)).toBe(true);

    frame(1500);
    expect(textOf(doc)).toBe(FIRST);
    expect(doc.getAttribute("aria-busy")).toBeNull();
    // Finished, so it stops asking for frames.
    expect(queue).toHaveLength(0);
  });

  it("pauses after finishing a run, so it reads as composed lines rather than one stream", () => {
    const { getByTestId } = render(<Host paragraphs={[FIRST, SECOND]} />);
    const doc = getByTestId("doc");

    frame(0);
    frame(500);
    // The frame that crosses a run boundary is what arms the beat, so this is where it starts.
    frame(1000);
    const atBoundary = textOf(doc);
    expect(atBoundary.startsWith(FIRST)).toBe(true);
    expect(atBoundary.length).toBeLessThan(FIRST.length + SECOND.length);

    // Held for the full 120ms beat — frames keep running, the reveal does not advance.
    frame(1050);
    frame(1110);
    expect(textOf(doc)).toBe(atBoundary);

    frame(1130);
    expect(textOf(doc).length).toBeGreaterThan(atBoundary.length);

    frame(5000);
    expect(textOf(doc)).toBe(FIRST + SECOND);
  });

  it("restores the full text when unmounted mid-run", () => {
    const view = render(<Host />);
    frame(0);
    frame(300);
    expect(view.getByTestId("doc").textContent).not.toBe(FIRST);

    // The hook must put the document back before letting go of it — React is about to reuse or
    // discard those very text nodes.
    const doc = view.getByTestId("doc");
    view.unmount();
    expect(doc.textContent).toBe(FIRST);
    expect(cancelled.length).toBeGreaterThan(0);
  });

  it("does nothing when disabled — reduced motion gets the text, not an animation", () => {
    const { getByTestId } = render(<Host enabled={false} />);
    expect(queue).toHaveLength(0);
    expect(textOf(getByTestId("doc"))).toBe(FIRST);
  });

  it("does nothing without a document key", () => {
    const { getByTestId } = render(<Host docKey={null} />);
    expect(queue).toHaveLength(0);
    expect(textOf(getByTestId("doc"))).toBe(FIRST);
  });

  it("flags the caret while writing and clears it at the end", () => {
    const { getByTestId } = render(<Host withCaret />);
    const caret = getByTestId("caret");

    frame(0);
    expect(caret.hasAttribute("data-on")).toBe(true);

    frame(1500);
    expect(caret.hasAttribute("data-on")).toBe(false);
  });
});
