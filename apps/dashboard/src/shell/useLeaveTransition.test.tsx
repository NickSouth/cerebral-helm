import { act, cleanup, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { CENTER_EXIT_MS, useLeaveTransition } from "./useLeaveTransition";

/**
 * The centre's handover rule. React unmounts the old surface the instant state changes, which is
 * why a report swap used to blink — there is nothing left to animate. This hook buys the outgoing
 * content one exit's worth of life.
 *
 * The asymmetry is the whole design and is what these cases exist to hold: a *handover* and a
 * *close* wait, an *open* does not. Making opening symmetrical would be the obvious refactor and
 * would cost every surface an exit's delay before it appeared — a bug that reads as general
 * sluggishness rather than as a transition fault, which is exactly the kind that survives review.
 */

function Probe({ value }: { value: string | null }) {
  const { shown, leaving } = useLeaveTransition(value);
  return (
    <>
      <span data-testid="shown">{shown ?? "none"}</span>
      <span data-testid="leaving">{String(leaving)}</span>
    </>
  );
}

function shown(): string {
  return screen.getByTestId("shown").textContent ?? "";
}

function leaving(): string {
  return screen.getByTestId("leaving").textContent ?? "";
}

describe("useLeaveTransition", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    cleanup();
    vi.useRealTimers();
  });

  it("opens immediately — there is nothing on screen to leave", () => {
    const view = render(<Probe value={null} />);
    act(() => {
      view.rerender(<Probe value="brief" />);
    });
    // No timer advanced. Waiting here would make every surface take an exit to appear.
    expect(shown()).toBe("brief");
    expect(leaving()).toBe("false");
  });

  it("holds the outgoing value, marked leaving, for the length of the exit", () => {
    const view = render(<Probe value="brief" />);
    act(() => {
      view.rerender(<Probe value="schedule" />);
    });

    // Still the old document, and flagged so the exit styling can run on it.
    expect(shown()).toBe("brief");
    expect(leaving()).toBe("true");

    act(() => {
      vi.advanceTimersByTime(CENTER_EXIT_MS - 1);
    });
    expect(shown()).toBe("brief");

    act(() => {
      vi.advanceTimersByTime(1);
    });
    expect(shown()).toBe("schedule");
    expect(leaving()).toBe("false");
  });

  it("never shows both at once", () => {
    const view = render(<Probe value="brief" />);
    act(() => {
      view.rerender(<Probe value="schedule" />);
    });
    // Sequential, not a crossfade: two documents visible together read as two voices, and the
    // incoming surface types itself in — which cannot start until the space is actually free.
    expect(screen.getByTestId("shown").textContent).toBe("brief");
    expect(screen.queryByText("schedule")).toBeNull();
  });

  it("gives closing to nothing a full exit rather than vanishing", () => {
    const view = render(<Probe value="brief" />);
    act(() => {
      view.rerender(<Probe value={null} />);
    });
    expect(shown()).toBe("brief");
    expect(leaving()).toBe("true");

    act(() => {
      vi.advanceTimersByTime(CENTER_EXIT_MS);
    });
    expect(shown()).toBe("none");
    expect(leaving()).toBe("false");
  });

  it("lands on the newest value when it changes again mid-exit", () => {
    const view = render(<Probe value="brief" />);
    act(() => {
      view.rerender(<Probe value="schedule" />);
    });
    act(() => {
      vi.advanceTimersByTime(CENTER_EXIT_MS / 2);
      view.rerender(<Probe value="capture" />);
    });

    act(() => {
      vi.advanceTimersByTime(CENTER_EXIT_MS);
    });
    // The superseded swap must not fire after the newer one — that would land on `schedule`, a
    // document the user never asked for, for one full exit.
    expect(shown()).toBe("capture");
    expect(leaving()).toBe("false");
  });

  it("stays put when the value is re-set to what is already shown", () => {
    const view = render(<Probe value="brief" />);
    act(() => {
      view.rerender(<Probe value="brief" />);
    });
    expect(shown()).toBe("brief");
    expect(leaving()).toBe("false");
  });

  it("does not swap after unmount", () => {
    const view = render(<Probe value="brief" />);
    act(() => {
      view.rerender(<Probe value="schedule" />);
    });
    view.unmount();
    // A pending timer firing into a torn-down tree is the classic leak here; the effect's cleanup
    // is what prevents it.
    expect(() => {
      act(() => {
        vi.advanceTimersByTime(CENTER_EXIT_MS * 2);
      });
    }).not.toThrow();
  });
});
