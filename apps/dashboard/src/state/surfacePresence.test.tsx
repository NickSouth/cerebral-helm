import { act, cleanup, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

/**
 * NIC-152. This store carries one bit, and almost all of its behaviour is about *who is allowed to
 * set it*. The native shell is the only thing that can see the windows on a given display; the
 * browser focus fallback exists purely so the treatment can be built and tuned without the Mac
 * host. If the fallback ever spoke over the host, an external display with windows stacked on it
 * would snap back to fully present the moment the user clicked into CerebralHelm on the laptop —
 * the exact confusion the per-display trigger was chosen to avoid.
 *
 * The store is module-scoped by design (nine surfaces, one ambient fact), so each case re-imports
 * it to get a clean instance rather than reaching for a reset seam that production never uses.
 */

interface PresenceWindow extends Window {
  __cerebralPresence?: { set(receded: boolean): void };
}

async function freshModule() {
  vi.resetModules();
  delete (window as PresenceWindow).__cerebralPresence;
  return import("./surfacePresence");
}

/** Renders the current value, and subscribing is what installs the window listeners. */
function Probe({
  useSurfaceReceded,
  id = "receded"
}: {
  useSurfaceReceded: () => boolean;
  id?: string;
}) {
  return <span data-testid={id}>{String(useSurfaceReceded())}</span>;
}

function value(): string {
  return screen.getByTestId("receded").textContent ?? "";
}

/** The real events the fallback listens for. */
function browserBlur(): void {
  act(() => {
    window.dispatchEvent(new Event("blur"));
  });
}

function browserFocus(): void {
  act(() => {
    window.dispatchEvent(new Event("focus"));
  });
}

function native(receded: boolean): void {
  act(() => {
    (window as PresenceWindow).__cerebralPresence?.set(receded);
  });
}

describe("surfacePresence (NIC-152)", () => {
  beforeEach(() => {
    // jsdom reports the document as focused, which is the "nothing is covering me" starting point.
    vi.spyOn(document, "hasFocus").mockReturnValue(true);
  });

  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it("starts present — a surface never opens in the receded state", async () => {
    const { useSurfaceReceded } = await freshModule();
    render(<Probe useSurfaceReceded={useSurfaceReceded} />);
    expect(value()).toBe("false");
  });

  it("follows browser focus while no host is driving", async () => {
    const { useSurfaceReceded } = await freshModule();
    render(<Probe useSurfaceReceded={useSurfaceReceded} />);

    browserBlur();
    expect(value()).toBe("true");
    browserFocus();
    expect(value()).toBe("false");
  });

  it("seeds from the current focus state, so a surface mounting behind other work starts receded", async () => {
    vi.spyOn(document, "hasFocus").mockReturnValue(false);
    const { useSurfaceReceded } = await freshModule();
    render(<Probe useSurfaceReceded={useSurfaceReceded} />);
    // Not "snaps there on the next event" — the value is right on the first render.
    expect(value()).toBe("true");
  });

  it("lets the native shell drive", async () => {
    const { useSurfaceReceded } = await freshModule();
    render(<Probe useSurfaceReceded={useSurfaceReceded} />);

    native(true);
    expect(value()).toBe("true");
    native(false);
    expect(value()).toBe("false");
  });

  it("locks the browser fallback out permanently once the host has spoken", async () => {
    const { useSurfaceReceded } = await freshModule();
    render(<Probe useSurfaceReceded={useSurfaceReceded} />);

    native(false);
    // The window losing focus is not evidence about what is on this display; the host said present.
    browserBlur();
    expect(value()).toBe("false");

    native(true);
    // And regaining focus does not un-recede a display that is still covered.
    browserFocus();
    expect(value()).toBe("true");
  });

  it("keeps every subscriber on one surface in step", async () => {
    const { useSurfaceReceded } = await freshModule();
    render(
      <>
        <Probe useSurfaceReceded={useSurfaceReceded} id="a" />
        <Probe useSurfaceReceded={useSurfaceReceded} id="b" />
      </>
    );
    native(true);
    expect(screen.getByTestId("a").textContent).toBe("true");
    expect(screen.getByTestId("b").textContent).toBe("true");
  });
});
