import { act, render, screen, waitFor, within, fireEvent } from "@testing-library/react";
import { DashboardShell } from "../shell/DashboardShell";
import { ReportBlocks } from "./ReportRegion";
import type { ReportBlock } from "./reportDocument";
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
 * The Report region and the `report` dispatch target (docs/quick-actions/PLAN.md phase 2).
 * The region is the future conversation surface, so what is asserted here — the region opens
 * over the running field, blocks render from the document, action references resolve through the
 * dispatch registry, and the ambient greeting steps aside — is what must keep holding when a
 * model becomes the composer.
 */

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

/**
 * Opening is deliberately not synchronous any more: the ambient greeting has to finish leaving,
 * and then the incoming surface owes it a beat, before anything is written into the space it had
 * (`CenterStage`'s handover). Every case that just wants an open report awaits that; the ordering
 * itself is asserted once, below, rather than re-tested in each of them.
 */
async function openDailyBrief() {
  fireEvent.click(screen.getByRole("button", { name: "Daily brief" }));
  return await screen.findByRole("region", { name: "Daily brief report" });
}

describe("Report region", () => {
  it("is absent until a Report action opens it", () => {
    renderShell();
    expect(screen.queryByRole("region", { name: "Daily brief report" })).toBeNull();
  });

  it("opens from the daily-brief slot and renders the composed document", async () => {
    renderShell();
    const region = await openDailyBrief();

    // The greeting block, the time line, and the calendar list all come from the composer.
    expect(within(region).getByText(/^Good (morning|afternoon|evening)\.$/)).toBeInTheDocument();
    expect(within(region).getByText(/^It's .+ on .+\.$/)).toBeInTheDocument();
  });

  it("keeps the consciousness field mounted — the report composites over it, never replaces it", async () => {
    renderShell();
    await openDailyBrief();
    // The centre panel and its running field are still there; only the greeting steps aside.
    expect(screen.getByRole("region", { name: "Heimlich" })).toBeInTheDocument();
  });

  it("hides the ambient greeting while open, so two greetings never stack", async () => {
    renderShell();
    const ambient = document.querySelector(".heimlich__greeting");
    expect(ambient).not.toBeNull();

    await openDailyBrief();
    // The greeting LEAVES rather than vanishing (increment 4), so it is still mounted for one exit
    // while it recedes. What must not happen is two greetings reading at once, which is why this
    // waits for it to go rather than relaxing to "eventually maybe".
    await waitFor(() => expect(document.querySelector(".heimlich__greeting")).toBeNull());

    // Closing restores it — also after an exit, since the report has to leave first.
    fireEvent.click(screen.getByRole("button", { name: "Close the Daily brief report" }));
    await waitFor(() => expect(document.querySelector(".heimlich__greeting")).not.toBeNull());
  });

  it("toggles closed when its own slot is pressed again", async () => {
    renderShell();
    await openDailyBrief();
    fireEvent.click(screen.getByRole("button", { name: "Daily brief" }));
    // Closing is a LEAVE, not a removal (increment 4): the surface stays mounted and marked
    // `data-leaving` while it recedes, so the swap is a handover rather than a blink. It is gone
    // once the exit has run — which is what this now waits for.
    expect(screen.getByRole("region", { name: "Daily brief report" })).toHaveAttribute(
      "data-leaving"
    );
    await waitFor(() =>
      expect(screen.queryByRole("region", { name: "Daily brief report" })).toBeNull()
    );
  });

  it("closes when the mode changes, since a report belongs to the mode whose slot opened it", async () => {
    const { bridge } = renderShell();
    await openDailyBrief();

    await act(async () => {
      await bridge.applyMode({ modeId: "school" });
    });

    // School has no daily-brief slot; leaving it open would render a report the mode does not
    // offer, degraded against providers the mode does not carry.
    // Closing is a LEAVE, not a removal (increment 4): the surface stays mounted and marked
    // `data-leaving` while it recedes, so the swap is a handover rather than a blink. It is gone
    // once the exit has run — which is what this now waits for.
    await waitFor(() =>
      expect(screen.queryByRole("region", { name: "Daily brief report" })).toBeNull()
    );
  });

  it("does not dispatch a command — a report composes from state already in the dashboard", () => {
    const bridge = createMockCerebralBridge();
    const submissions: string[] = [];
    const spyBridge = {
      ...bridge,
      submitCommand(input: { rawInput: string; source: string }) {
        submissions.push(input.rawInput);
        return bridge.submitCommand(input);
      }
    };
    const store = createBridgeStore(spyBridge, loadBootstrapState());
    render(
      <BridgeProvider bridge={spyBridge}>
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
    );

    fireEvent.click(screen.getByRole("button", { name: "Daily brief" }));
    expect(submissions).toEqual([]);
  });
});

describe("Report action references", () => {
  function renderBlocks(blocks: ReportBlock[]) {
    const bridge = createMockCerebralBridge();
    const store = createBridgeStore(bridge, loadBootstrapState());
    return render(
      <BridgeProvider bridge={bridge}>
        <DashboardStateProvider store={store}>
          <AppearanceProvider>
            <ThemeProvider>
              <ActionStatusProvider>
                <SettingsProvider>
                  <ReportProvider>
                    <InputProvider>
                      <ReportBlocks blocks={blocks} />
                    </InputProvider>
                  </ReportProvider>
                </SettingsProvider>
              </ActionStatusProvider>
            </ThemeProvider>
          </AppearanceProvider>
        </DashboardStateProvider>
      </BridgeProvider>
    );
  }

  it("makes a reference to a BUILT action clickable, including one that opens another surface", () => {
    renderBlocks([
      {
        blockKind: "count",
        value: "3",
        label: "unread",
        reportAction: { action: "capture-note" }
      }
    ]);
    // capture-note opens the Input region: a report's proposal must be able to reach every
    // archetype, not just the ones that dispatch to the command bus.
    expect(screen.getByRole("button")).toHaveTextContent("3");
  });

  it("renders a reference to an unregistered action as plain text, not a dead control", () => {
    // An action nobody registered may never become a clickable control: a report stays readable,
    // it just isn't clickable, and a model can never mint a destination by naming one.
    //
    // This used to also cover "registered but not built yet", with `email-report` as the example.
    // Every registered action now has a dispatch target (Gmail integration, 2026-08-04), so there
    // is no such action left to test with — the guard itself still stands in `quickActionTarget`.
    renderBlocks([
      { blockKind: "count", value: "3", label: "unread", reportAction: { action: "not-registered" } },
      {
        blockKind: "line",
        text: "Somewhere else",
        reportAction: { action: "not-a-real-action" }
      }
    ]);
    expect(screen.queryByRole("button")).toBeNull();
    expect(screen.getByText("Somewhere else")).toBeInTheDocument();
  });

  it("renders each block kind from the fields its own kind declares", () => {
    renderBlocks([
      { blockKind: "greeting", text: "Good morning.", greetingSize: "hero" },
      { blockKind: "metric", label: "Outside", value: "72°F", metricTone: "neutral" },
      {
        blockKind: "checklist",
        listItems: [
          { text: "Contract drift", status: "passed" },
          { text: "Swift tests", status: "running" }
        ]
      },
      { blockKind: "empty", text: "Nothing yet." },
      { blockKind: "proposal", text: "Your evening is clear.", reportActions: [] }
    ]);

    expect(screen.getByText("Good morning.")).toHaveAttribute("data-size", "hero");
    expect(screen.getByText("72°F")).toBeInTheDocument();
    expect(screen.getByText("Nothing yet.")).toHaveClass("report-empty");
    expect(screen.getByText("Your evening is clear.")).toBeInTheDocument();
    // A checklist carries its status as text too, never colour alone (§5.8).
    const list = screen.getByRole("list");
    expect(within(list).getByText("passed")).toBeInTheDocument();
    expect(within(list).getByText("running")).toBeInTheDocument();
  });
});
