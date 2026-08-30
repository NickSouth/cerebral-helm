import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import { DashboardShell } from "./DashboardShell";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { BridgeProvider } from "../state/BridgeProvider";
import { ActionStatusProvider } from "../state/ActionStatusProvider";
import { SettingsProvider } from "../state/SettingsProvider";
import { ReportProvider } from "../state/ReportProvider";
import { InputProvider } from "../state/InputProvider";
import { AppearanceProvider } from "../state/AppearanceProvider";
import { ThemeProvider } from "../app/ThemeProvider";
import { createBridgeStore } from "../state/bridgeStore";
import { createMockCerebralBridge, loadBootstrapState } from "../bridge/mockCerebralBridge";

/**
 * The centre's handover.
 *
 * This exists because the sequence was designed, half-built, and shipped broken: `CENTER_BEAT_MS`
 * was written and never referenced, and each surface opened the instant it was asked to — landing
 * on top of an ambient greeting that was still fading out. It read as a stutter, which is exactly
 * what it was.
 *
 * The property is **ordering**, not duration, so nothing here asserts a millisecond count: the
 * greeting must be gone before its replacement is on screen, and the two must never be visible
 * together. Timings are tunable; the sequence is not.
 */

afterEach(cleanup);

function renderShell() {
  const bridge = createMockCerebralBridge();
  const store = createBridgeStore(bridge, loadBootstrapState());
  return {
    bridge,
    ...render(
      <BridgeProvider bridge={bridge}>
        <DashboardStateProvider store={store}>
          <AppearanceProvider>
            <ThemeProvider>
              <ActionStatusProvider>
                <SettingsProvider>
                  <ReportProvider>
                    <InputProvider>
                      <DashboardShell />
                    </InputProvider>
                  </ReportProvider>
                </SettingsProvider>
              </ActionStatusProvider>
            </ThemeProvider>
          </AppearanceProvider>
        </DashboardStateProvider>
      </BridgeProvider>
    )
  };
}

const greeting = () => document.querySelector(".heimlich__greeting");
const report = () => screen.queryByRole("region", { name: "Daily brief report" });
const form = () => screen.queryByRole("region", { name: "Capture note form" });

describe("CenterStage handover", () => {
  it("never shows the greeting and a report at the same time", async () => {
    renderShell();
    expect(greeting()).not.toBeNull();

    fireEvent.click(screen.getByRole("button", { name: "Daily brief" }));

    // The regression this guards: the report used to mount immediately, over a greeting still
    // mid-fade. Poll the whole transition and assert the overlap never occurs at any point.
    let overlapped = false;
    await waitFor(
      () => {
        if (greeting() && report()) {
          overlapped = true;
        }
        expect(report()).not.toBeNull();
      },
      { interval: 10 }
    );
    expect(overlapped).toBe(false);
    expect(greeting()).toBeNull();
  });

  it("never shows the greeting and an input at the same time", async () => {
    renderShell();
    fireEvent.click(screen.getByRole("button", { name: "Capture note" }));

    let overlapped = false;
    await waitFor(
      () => {
        if (greeting() && form()) {
          overlapped = true;
        }
        expect(form()).not.toBeNull();
      },
      { interval: 10 }
    );
    expect(overlapped).toBe(false);
  });

  it("brings the greeting back only after the surface has left", async () => {
    renderShell();
    fireEvent.click(screen.getByRole("button", { name: "Daily brief" }));
    await screen.findByRole("region", { name: "Daily brief report" });
    expect(greeting()).toBeNull();

    fireEvent.click(screen.getByRole("button", { name: "Close the Daily brief report" }));

    let overlapped = false;
    await waitFor(
      () => {
        if (greeting() && report()) {
          overlapped = true;
        }
        expect(greeting()).not.toBeNull();
      },
      { interval: 10 }
    );
    // The reverse direction matters just as much: a greeting written back in underneath a report
    // still receding is the same collision, just less obvious.
    expect(overlapped).toBe(false);
  });

  it("does not charge a handover when the second surface opens", async () => {
    renderShell();
    fireEvent.click(screen.getByRole("button", { name: "Daily brief" }));
    await screen.findByRole("region", { name: "Daily brief report" });

    // The greeting is already gone, so there is nothing to hand over from. A form opening now must
    // not wait — paying an exit for a transition that is not happening is how a handover turns
    // into general sluggishness.
    fireEvent.click(screen.getByRole("button", { name: "Capture note" }));
    await act(async () => {});
    expect(form()).not.toBeNull();
  });

  it("keeps the report and the input coexisting — they share the centre, the greeting yields to both", async () => {
    renderShell();
    fireEvent.click(screen.getByRole("button", { name: "Daily brief" }));
    await screen.findByRole("region", { name: "Daily brief report" });
    fireEvent.click(screen.getByRole("button", { name: "Capture note" }));
    await screen.findByRole("region", { name: "Capture note form" });

    expect(report()).not.toBeNull();
    expect(form()).not.toBeNull();
    expect(greeting()).toBeNull();
  });

  it("puts the report and the form in one row, so neither takes height from the other", async () => {
    // jsdom does not lay out, so this asserts the STRUCTURE the layout depends on rather than the
    // pixels. It is worth pinning because the bug it replaces was invisible in every unit test:
    // the report sat in `.heimlich`'s column and the form inside `.heimlich__foot` beneath it, so
    // opening a 458px form on the right shrank the report on the left to 92px and clipped 117px
    // of a brief — with 604px of panel standing empty below it. They render on opposite sides and
    // never overlap; only the shared column made one cost the other.
    //
    // Moving the form back under the foot would restore that silently, which is why the sibling
    // relationship is the assertion.
    renderShell();
    fireEvent.click(screen.getByRole("button", { name: "Daily brief" }));
    await screen.findByRole("region", { name: "Daily brief report" });
    fireEvent.click(screen.getByRole("button", { name: "Capture note" }));
    await screen.findByRole("region", { name: "Capture note form" });

    const band = document.querySelector(".heimlich__surfaces");
    expect(band).not.toBeNull();
    expect(band?.contains(report()!)).toBe(true);
    expect(band?.contains(form()!)).toBe(true);
    expect(document.querySelector(".heimlich__foot")?.contains(form()!)).toBe(false);
  });
});
