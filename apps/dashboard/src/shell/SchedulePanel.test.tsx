import { render, screen, fireEvent } from "@testing-library/react";
import { describe, it, expect } from "vitest";
import { SchedulePanel } from "./SchedulePanel";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { BridgeProvider } from "../state/BridgeProvider";
import { ActionStatusProvider } from "../state/ActionStatusProvider";
import { createBridgeStore } from "../state/bridgeStore";
import { createMockCerebralBridge } from "../bridge/mockCerebralBridge";
import { getDashboardConfigBundle, getDashboardFixture } from "../fixtures/canonicalFixtures";
import type { DashboardState } from "../state/dashboardState";

/** Active mode is Executive → calendarProfile "all". Wraps the bridge/status providers the
 *  "View full schedule" control depends on, and records the raw commands the bridge receives. */
function renderPanel(mutate: (base: DashboardState) => DashboardState) {
  const bridge = createMockCerebralBridge();
  const submissions: string[] = [];
  const spyBridge = {
    ...bridge,
    submitCommand(input: { rawInput: string; source: string }) {
      submissions.push(input.rawInput);
      return bridge.submitCommand(input);
    }
  };
  const base: DashboardState = {
    ...getDashboardConfigBundle(),
    ...getDashboardFixture("mode.executive.ready")
  };
  const store = createBridgeStore(spyBridge, mutate(base));
  render(
    <BridgeProvider bridge={spyBridge}>
      <DashboardStateProvider store={store}>
        <ActionStatusProvider>
          <SchedulePanel now={new Date("2026-07-27T12:00:00Z")} />
        </ActionStatusProvider>
      </DashboardStateProvider>
    </BridgeProvider>
  );
  return { submissions };
}

describe("SchedulePanel", () => {
  it("resolves live per-profile schedule over the bootstrap region, in 12-hour time (NIC-126)", () => {
    renderPanel((base) => ({
      ...base,
      liveSchedule: {
        all: {
          state: "ready",
          items: [
            { id: "s1", title: "Live planning review", start: "2026-07-27T14:00:00", kind: "today" },
            { id: "s2", title: "Live evening rehearsal", start: "2026-07-27T23:00:00", kind: "tonight" }
          ]
        }
      }
    }));
    expect(screen.getByText("Live planning review")).toBeInTheDocument();
    expect(screen.getByText("Live evening rehearsal")).toBeInTheDocument();
    // Times render 12-hour with AM/PM, not 24-hour.
    expect(screen.getByText("2:00 PM")).toBeInTheDocument();
    expect(screen.getByText("11:00 PM")).toBeInTheDocument();
    expect(screen.queryByText("14:00")).toBeNull();
    expect(screen.queryByText("23:00")).toBeNull();
  });

  it("shows the event location as a hover tooltip on the row, omitting it when absent (NIC-126)", () => {
    renderPanel((base) => ({
      ...base,
      liveSchedule: {
        all: {
          state: "ready",
          items: [
            { id: "s1", title: "Design review", start: "2026-07-27T14:00:00", kind: "today", location: "Room 4B" },
            { id: "s2", title: "No-location event", start: "2026-07-27T15:00:00", kind: "today" }
          ]
        }
      }
    }));
    expect(screen.getByText("Design review").closest("li")).toHaveAttribute("title", "Room 4B");
    expect(screen.getByText("No-location event").closest("li")).not.toHaveAttribute("title");
  });

  it("falls back to the bootstrap region when no live schedule for the active profile", () => {
    renderPanel((base) => ({
      ...base,
      regions: {
        ...base.regions,
        schedule: {
          state: "ready",
          items: [{ id: "b1", title: "Bootstrap standup", start: "2026-07-27T15:00:00", kind: "today" }]
        }
      },
      liveSchedule: {
        engineering: {
          state: "ready",
          items: [{ id: "e1", title: "Engineering-only sync", start: "2026-07-27T17:00:00", kind: "today" }]
        }
      }
    }));
    expect(screen.getByText("Bootstrap standup")).toBeInTheDocument();
    expect(screen.queryByText("Engineering-only sync")).toBeNull();
  });

  it("opens the Calendar app via the open-app grammar when View full schedule is clicked (NIC-126)", () => {
    const { submissions } = renderPanel((base) => base);
    fireEvent.click(screen.getByRole("button", { name: /View full schedule/ }));
    expect(submissions).toEqual(["open calendar"]);
  });

  it("disables View full schedule and dispatches nothing while the dashboard is read-only", () => {
    const { submissions } = renderPanel((base) => ({
      ...base,
      recovery: { reason: "bridge_failure", startupMode: "recovery" }
    }));
    const button = screen.getByRole("button", { name: /View full schedule/ });
    expect(button).toBeDisabled();
    fireEvent.click(button);
    expect(submissions).toEqual([]);
  });
});
