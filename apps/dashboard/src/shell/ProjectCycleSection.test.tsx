import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { describe, it, expect, vi, beforeEach } from "vitest";
import {
  ProjectCycleSection,
  groupByStatus,
  formatCycleRange,
  daysRemaining
} from "./ProjectCycleSection";
import type { GetLinearProjectCycleResult, LinearCycleIssue } from "../bridge/cerebralBridge";

/** NIC-221: the project detail window's Linear cycle section.
 *
 *  The bulk of this suite is about the SIX ways the section can hold no rows. Five of them are the
 *  user's to act on, and collapsing any into a bare "nothing to do" is the failure that matters
 *  here — a confident wrong answer that looks like an answer. */

const getLinearProjectCycle = vi.fn();
const submitCommand = vi.fn(() => Promise.resolve({ accepted: true }));
let readOnly = false;

vi.mock("../state/BridgeProvider", () => ({
  useBridge: () => ({ getLinearProjectCycle, submitCommand })
}));
vi.mock("../state/useUiPosture", () => ({ useUiPosture: () => ({ readOnly }) }));

function issue(overrides: Partial<LinearCycleIssue> = {}): LinearCycleIssue {
  return {
    identifier: "NIC-1",
    title: "An issue",
    url: "https://linear.app/x/issue/NIC-1",
    priority: 0,
    estimate: null,
    sortOrder: 0,
    state: { name: "Todo", type: "unstarted", color: "#e2e2e2", position: 1 },
    labels: [],
    assignee: null,
    assigneeInitials: null,
    ...overrides
  };
}

function result(overrides: Partial<GetLinearProjectCycleResult> = {}): GetLinearProjectCycleResult {
  return {
    matchedProject: "CerebralHelm",
    matchedProjectUrl: "https://linear.app/x/project/ch",
    cycle: {
      id: "c2",
      number: 2,
      name: null,
      startsAt: "2026-08-17T04:00:00.000Z",
      endsAt: "2026-08-24T04:00:00.000Z"
    },
    issues: [],
    truncated: false,
    available: true,
    reason: null,
    ...overrides
  };
}

const renderSection = (linearProject: string | null = "CerebralHelm") =>
  render(<ProjectCycleSection linearProject={linearProject} />);

beforeEach(() => {
  readOnly = false;
  getLinearProjectCycle.mockReset();
  submitCommand.mockClear();
  getLinearProjectCycle.mockResolvedValue(result());
});

describe("ProjectCycleSection — the states that are not a list", () => {
  it("an unlinked project asks to be linked, and never calls the bridge", () => {
    renderSection(null);
    expect(screen.getByText(/Not linked to Linear/i)).toBeTruthy();
    expect(getLinearProjectCycle).not.toHaveBeenCalled();
  });

  it("a host with no Linear client points at Settings, not at an empty cycle", async () => {
    getLinearProjectCycle.mockResolvedValue(result({ available: false }));
    renderSection();
    expect(await screen.findByText(/isn.t set up/i)).toBeTruthy();
  });

  it("a failed read reports the reason rather than claiming there is nothing", async () => {
    getLinearProjectCycle.mockResolvedValue(result({ reason: "Linear returned HTTP 500." }));
    renderSection();
    expect(await screen.findByText(/HTTP 500/)).toBeTruthy();
  });

  it("a rejected promise is caught and surfaced, not left as a spinner", async () => {
    getLinearProjectCycle.mockRejectedValue(new Error("bridge died"));
    renderSection();
    expect(await screen.findByText(/Couldn.t reach Linear/i)).toBeTruthy();
  });

  it("a name matching no project names the typo instead of showing an empty cycle", async () => {
    getLinearProjectCycle.mockResolvedValue(
      result({ matchedProject: null, matchedProjectUrl: null, cycle: null })
    );
    renderSection("CerebralHlem");
    expect(await screen.findByText(/No Linear project by that name/i)).toBeTruthy();
    // The exact string the user has to fix appears, so the fix needs no guessing.
    expect(screen.getByText("CerebralHlem")).toBeTruthy();
  });

  it("no running cycle is its own state, distinct from an empty one", async () => {
    getLinearProjectCycle.mockResolvedValue(result({ cycle: null }));
    renderSection();
    expect(await screen.findByText(/No cycle running/i)).toBeTruthy();
  });

  it("a matched project with an empty cycle names the cycle it is empty for", async () => {
    renderSection();
    expect(await screen.findByText(/Nothing in this cycle/i)).toBeTruthy();
    expect(screen.getByText(/Cycle 2/)).toBeTruthy();
  });
});

describe("ProjectCycleSection — the list", () => {
  const populated = result({
    issues: [
      issue({
        identifier: "NIC-224",
        title: "Report types with bullet points FIX",
        state: { name: "Testing", type: "started", color: "#f2994a", position: 907 },
        labels: ["Bug"],
        estimate: 1,
        assignee: "nickrsouthey",
        assigneeInitials: "NS",
        sortOrder: 2
      }),
      issue({
        identifier: "NIC-225",
        title: "Model provider port",
        state: { name: "Done", type: "completed", color: "#34d399", position: 1300 },
        sortOrder: 1
      }),
      issue({
        identifier: "NIC-227",
        title: "Grammar-constrained decoding",
        state: { name: "Todo", type: "unstarted", color: "#e2e2e2", position: 1 },
        sortOrder: 3
      })
    ]
  });

  it("renders every issue, grouped under its status", async () => {
    getLinearProjectCycle.mockResolvedValue(populated);
    renderSection();
    expect(await screen.findByText("Testing")).toBeTruthy();
    expect(screen.getByText("Todo")).toBeTruthy();
    expect(screen.getByText("Done")).toBeTruthy();
    expect(screen.getByText("NIC-224")).toBeTruthy();
    expect(screen.getByText("NIC-227")).toBeTruthy();
  });

  it("counts only completed issues as done", async () => {
    getLinearProjectCycle.mockResolvedValue(populated);
    renderSection();
    expect(await screen.findByText("1 / 3 done")).toBeTruthy();
  });

  it("opens an issue in Linear through the web.open grammar", async () => {
    getLinearProjectCycle.mockResolvedValue(populated);
    renderSection();
    fireEvent.click(await screen.findByTitle("Open NIC-224 in Linear"));
    expect(submitCommand).toHaveBeenCalledWith({
      rawInput: "web https://linear.app/x/issue/NIC-1",
      source: "dashboard"
    });
  });

  it("read-only recovery disables opening rather than hiding the rows", async () => {
    readOnly = true;
    getLinearProjectCycle.mockResolvedValue(populated);
    renderSection();
    const row = (await screen.findByText("NIC-224")).closest("button");
    expect((row as HTMLButtonElement).disabled).toBe(true);
    fireEvent.click(row as HTMLButtonElement);
    expect(submitCommand).not.toHaveBeenCalled();
  });

  it("says so when the list was cut at a page boundary", async () => {
    getLinearProjectCycle.mockResolvedValue({ ...populated, truncated: true });
    renderSection();
    expect(await screen.findByText(/more than one page/i)).toBeTruthy();
  });

  it("shows a skeleton before the data lands, never an empty state", async () => {
    let settle: (value: GetLinearProjectCycleResult) => void = () => {};
    getLinearProjectCycle.mockReturnValue(
      new Promise<GetLinearProjectCycleResult>((resolve) => {
        settle = resolve;
      })
    );
    const { container } = renderSection();
    // Flashing "Nothing in this cycle" while still loading would be a wrong answer, briefly.
    expect(screen.queryByText(/Nothing in this cycle/i)).toBeNull();
    expect(container.querySelector(".cyc__loading")).toBeTruthy();
    settle(populated);
    await waitFor(() => expect(screen.getByText("NIC-224")).toBeTruthy());
  });
});

describe("groupByStatus", () => {
  it("orders most-active-first, then by Linear's own workflow position", () => {
    const groups = groupByStatus([
      issue({ identifier: "d", state: { name: "Done", type: "completed", color: "#0", position: 5 } }),
      issue({ identifier: "t", state: { name: "Todo", type: "unstarted", color: "#0", position: 2 } }),
      issue({ identifier: "n", state: { name: "Next-Up", type: "unstarted", color: "#0", position: 1 } }),
      issue({ identifier: "p", state: { name: "Testing", type: "started", color: "#0", position: 9 } })
    ]);
    // Started first — what you are doing outranks what you finished. Within `unstarted`, Linear's
    // position decides, so reordering statuses in Linear reorders them here with no code change.
    expect(groups.map((group) => group.name)).toEqual(["Testing", "Next-Up", "Todo", "Done"]);
  });

  it("orders issues within a group by Linear's manual sortOrder", () => {
    const [group] = groupByStatus([
      issue({ identifier: "second", sortOrder: 50 }),
      issue({ identifier: "first", sortOrder: -77240 })
    ]);
    expect(group.issues.map((i) => i.identifier)).toEqual(["first", "second"]);
  });

  it("puts an unknown state type last rather than dropping its issues", () => {
    // A workflow type this build has never heard of must still show up — losing issues silently
    // is exactly the failure this surface is built to avoid.
    const groups = groupByStatus([
      issue({ identifier: "weird", state: { name: "Zzz", type: "invented", color: "#0", position: 1 } }),
      issue({ identifier: "normal", state: { name: "Testing", type: "started", color: "#0", position: 1 } })
    ]);
    expect(groups.map((group) => group.name)).toEqual(["Testing", "Zzz"]);
  });
});

describe("cycle header formatting", () => {
  it("collapses a shared month into one label", () => {
    expect(formatCycleRange("2026-08-17T04:00:00.000Z", "2026-08-24T04:00:00.000Z")).toMatch(
      /^17–24 \w+$/
    );
  });

  it("keeps both months when the cycle spans a boundary", () => {
    expect(formatCycleRange("2026-08-28T04:00:00.000Z", "2026-09-04T04:00:00.000Z")).toMatch(
      /^28 \w+ – 4 \w+$/
    );
  });

  it("counts whole days left, and reports none once the cycle has closed", () => {
    const now = new Date("2026-08-20T12:00:00.000Z");
    expect(daysRemaining("2026-08-24T04:00:00.000Z", now)).toBe(4);
    expect(daysRemaining("2026-08-19T04:00:00.000Z", now)).toBeNull();
  });

  it("does not crash on an unparseable timestamp", () => {
    expect(formatCycleRange("not-a-date", "also-not")).toBe("");
    expect(daysRemaining("not-a-date")).toBeNull();
  });
});
