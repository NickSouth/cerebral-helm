import { act, cleanup, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
/** Read from the module rather than restated here, so a retune of the sequence cannot leave these
 *  cases silently asserting against a duration that no longer exists. This import is only for the
 *  constant — every case drives a freshly re-imported instance of the module itself. */
import { TOTAL_MS } from "./useStartupIntro";

/**
 * NIC-157. The sequence is a *launch* animation, and the one thing it must never do is play again
 * while the app is running — a mode switch re-renders the whole shell, and StrictMode
 * double-invokes effects in development. Replaying on either would make CerebralHelm look like it
 * had just restarted itself.
 *
 * That is why "once" is scoped to the module rather than to a mount, and why these cases re-import
 * the module to get a fresh page load instead of using the reset seam: the seam exists for tests
 * that need to drive the sequence twice deliberately, and using it here would test the seam rather
 * than the lifetime.
 */

async function freshModule() {
  vi.resetModules();
  return import("./useStartupIntro");
}

type IntroModule = Awaited<ReturnType<typeof freshModule>>;

function Probe({ mod, ready }: { mod: IntroModule; ready: boolean }) {
  const active = mod.useStartupIntro(ready);
  const start = mod.useFieldIntroStart();
  return (
    <>
      <span data-testid="active">{String(active)}</span>
      <span data-testid="start">{start === null ? "null" : "number"}</span>
    </>
  );
}

function active(): string {
  return screen.getByTestId("active").textContent ?? "";
}

function fieldStart(): string {
  return screen.getByTestId("start").textContent ?? "";
}

describe("useStartupIntro (NIC-157)", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    cleanup();
    vi.useRealTimers();
  });

  it("waits for the dashboard to be ready before starting", async () => {
    const mod = await freshModule();
    render(<Probe mod={mod} ready={false} />);
    // Playing over a skeleton would introduce a loading state and leave the real shell to pop in
    // afterwards, which is the opposite of what the sequence is for.
    expect(active()).toBe("false");
    expect(fieldStart()).toBe("null");
  });

  it("starts once ready, and hands the shader a clock to derive its own progress from", async () => {
    const mod = await freshModule();
    const view = render(<Probe mod={mod} ready={false} />);
    act(() => {
      view.rerender(<Probe mod={mod} ready />);
    });
    expect(active()).toBe("true");
    // A timestamp, not a boolean: the field animates per frame without React re-rendering for it.
    expect(fieldStart()).toBe("number");
  });

  it("ends itself, and reports a finished sequence to the shader as 'no intro'", async () => {
    const mod = await freshModule();
    render(<Probe mod={mod} ready />);
    expect(active()).toBe("true");

    act(() => {
      vi.advanceTimersByTime(TOTAL_MS);
    });
    expect(active()).toBe("false");
    // Null tells the shader to render its finished steady state immediately rather than replay.
    expect(fieldStart()).toBe("null");
  });

  it("does not replay when the shell remounts — a mode switch is not a launch", async () => {
    const mod = await freshModule();
    const first = render(<Probe mod={mod} ready />);
    expect(active()).toBe("true");

    act(() => {
      vi.advanceTimersByTime(TOTAL_MS);
    });
    first.unmount();

    // The same page load, a brand-new tree — exactly what a mode switch produces.
    render(<Probe mod={mod} ready />);
    expect(active()).toBe("false");
    expect(fieldStart()).toBe("null");
  });

  it("does not restart when `ready` flaps while the sequence is running", async () => {
    const mod = await freshModule();
    const view = render(<Probe mod={mod} ready />);
    act(() => {
      vi.advanceTimersByTime(TOTAL_MS / 2);
    });
    act(() => {
      view.rerender(<Probe mod={mod} ready={false} />);
      view.rerender(<Probe mod={mod} ready />);
    });

    // Still on the original clock: half the sequence had already elapsed, so the other half
    // finishes it. A restart at the flap would have left it active here.
    act(() => {
      vi.advanceTimersByTime(TOTAL_MS / 2);
    });
    expect(active()).toBe("false");
  });

  it("plays again after a genuinely new page load", async () => {
    const first = await freshModule();
    render(<Probe mod={first} ready />);
    act(() => {
      vi.advanceTimersByTime(TOTAL_MS);
    });
    cleanup();

    // Each surface's webview is its own module instance, so every display plays its own sequence.
    const second = await freshModule();
    render(<Probe mod={second} ready />);
    expect(active()).toBe("true");
  });
});
