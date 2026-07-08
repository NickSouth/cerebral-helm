import { render } from "@testing-library/react";
import { useRef } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { BeamOverlay } from "./BeamOverlay";
import { useAmbientBeam } from "./useAmbientBeam";

/**
 * NIC-122: the beams must move by per-element `transform` writes (compositor-only), never by
 * paint-affecting properties — the previous CSS-var + background-position implementation
 * re-rastered every outline overlay each frame and leaked the web process to multiple GB.
 */

function Host() {
  const ref = useRef<HTMLDivElement>(null);
  useAmbientBeam(ref);
  return (
    <div ref={ref} data-testid="root">
      <section className="shell-panel">
        <BeamOverlay />
      </section>
      <section className="heimlich">
        <BeamOverlay />
      </section>
    </div>
  );
}

const PARKED = "";

describe("useAmbientBeam", () => {
  let rafQueue: FrameRequestCallback[];

  beforeEach(() => {
    vi.useFakeTimers();
    rafQueue = [];
    vi.stubGlobal("requestAnimationFrame", (cb: FrameRequestCallback) => {
      rafQueue.push(cb);
      return rafQueue.length;
    });
    vi.stubGlobal("cancelAnimationFrame", () => {});
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.useRealTimers();
  });

  function runFrame(time: number) {
    const pending = rafQueue.splice(0);
    for (const cb of pending) cb(time);
  }

  it("writes translate3d transforms to every overlay light tile during a pass", () => {
    const { container } = render(<Host />);
    const beamALights = container.querySelectorAll<HTMLElement>(
      '.beam-overlay__light[data-beam="a"]'
    );
    expect(beamALights).toHaveLength(2);
    for (const light of beamALights) expect(light.style.transform).toBe(PARKED);

    // Beam "a" starts with zero delay; its first frame is scheduled by the timer.
    vi.advanceTimersByTime(0);
    runFrame(performance.now());

    for (const light of beamALights) {
      expect(light.style.transform).toMatch(/^translate3d\(-?[\d.]+px, -?[\d.]+px, 0\)$/);
    }
  });

  it("moves the tiles between frames (the pass actually sweeps)", () => {
    const { container } = render(<Host />);
    const light = container.querySelector<HTMLElement>('.beam-overlay__light[data-beam="a"]')!;

    vi.advanceTimersByTime(0);
    const t0 = performance.now();
    runFrame(t0);
    const first = light.style.transform;
    runFrame(t0 + 1000);
    const second = light.style.transform;

    expect(first).not.toBe(second);
  });

  it("does not run under prefers-reduced-motion", () => {
    vi.stubGlobal(
      "matchMedia",
      vi.fn().mockReturnValue({
        matches: true,
        addEventListener: vi.fn(),
        removeEventListener: vi.fn()
      })
    );
    const { container } = render(<Host />);

    vi.advanceTimersByTime(5000);
    runFrame(performance.now());

    const lights = container.querySelectorAll<HTMLElement>(".beam-overlay__light");
    for (const light of lights) expect(light.style.transform).toBe(PARKED);
  });

  it("stops writing after unmount", () => {
    const { container, unmount } = render(<Host />);
    const light = container.querySelector<HTMLElement>('.beam-overlay__light[data-beam="a"]')!;

    vi.advanceTimersByTime(0);
    const t0 = performance.now();
    runFrame(t0);
    const atUnmount = light.style.transform;

    unmount();
    runFrame(t0 + 1000);
    vi.advanceTimersByTime(10_000);
    runFrame(t0 + 2000);

    expect(light.style.transform).toBe(atUnmount);
  });
});
