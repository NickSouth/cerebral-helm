import { render, screen, within, fireEvent, act } from "@testing-library/react";
import { DashboardShell } from "./DashboardShell";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { BridgeProvider } from "../state/BridgeProvider";
import { ConversationProvider } from "../state/ConversationProvider";
import { ThemeProvider } from "../app/ThemeProvider";
import { createBridgeStore } from "../state/bridgeStore";
import { createMockCerebralBridge, loadBootstrapState } from "../bridge/mockCerebralBridge";
import { getDashboardConfigBundle, getDashboardFixture } from "../fixtures/canonicalFixtures";
import type { DashboardState } from "../state/dashboardState";

function renderProviders(bridge: ReturnType<typeof createMockCerebralBridge>, store: ReturnType<typeof createBridgeStore>) {
  return render(
    <BridgeProvider bridge={bridge}>
      <DashboardStateProvider store={store}>
        <ThemeProvider>
          <ConversationProvider>
            <DashboardShell />
          </ConversationProvider>
        </ThemeProvider>
      </DashboardStateProvider>
    </BridgeProvider>
  );
}

/** Render the shell over a bridge-backed store. With no key, boots the default mode (Executive). */
function renderShell(canonicalKey?: string) {
  const bridge = canonicalKey ? createMockCerebralBridge({ bootstrapKey: canonicalKey }) : createMockCerebralBridge();
  const initial = canonicalKey ? { ...getDashboardConfigBundle(), ...getDashboardFixture(canonicalKey) } : loadBootstrapState();
  const store = createBridgeStore(bridge, initial);
  return { bridge, ...renderProviders(bridge, store) };
}

/** Render the shell with an arbitrary state override (for degraded-state coverage, NIC-64). */
function renderShellWithState(mutate: (base: DashboardState) => DashboardState) {
  const bridge = createMockCerebralBridge();
  const base: DashboardState = { ...getDashboardConfigBundle(), ...getDashboardFixture("mode.executive.ready") };
  const store = createBridgeStore(bridge, mutate(base));
  return { bridge, ...renderProviders(bridge, store) };
}

function selectedModeButton() {
  return within(screen.getByRole("group", { name: "Mode" }))
    .getAllByRole("button")
    .find((button) => button.getAttribute("aria-pressed") === "true");
}

describe("DashboardShell structure", () => {
  it("makes the Heimlich center the main region (the main product is immediately visible)", () => {
    renderShell();
    const main = document.getElementById("main");
    expect(main).not.toBeNull();
    expect(within(main as HTMLElement).getByRole("region", { name: "Heimlich" })).toBeInTheDocument();
  });

  it("renders the three zones plus the persistent bottom bar", () => {
    renderShell();
    expect(screen.getByRole("complementary", { name: "Information" })).toBeInTheDocument();
    expect(screen.getByRole("complementary", { name: "Operations" })).toBeInTheDocument();
    expect(screen.getByRole("contentinfo", { name: "Status bar" })).toBeInTheDocument();
  });

  it("boots Executive (the default mode) with exactly one mode control selected", () => {
    renderShell();
    const options = within(screen.getByRole("group", { name: "Mode" })).getAllByRole("button");
    expect(options).toHaveLength(4);
    expect(selectedModeButton()).toHaveTextContent("Executive");
  });

  it("renders the fixed four-agent roster", () => {
    renderShell();
    for (const name of ["Research Analyst", "Financial Advisor", "Project Manager", "System Janitor"]) {
      expect(screen.getByText(name)).toBeInTheDocument();
    }
  });

  it("renders eight quick-action slots — wired ones enabled, placeholders disabled", () => {
    renderShell();
    const slots = within(screen.getByRole("group", { name: "Quick actions" })).getAllByRole("button");
    expect(slots).toHaveLength(8);
    // D4 wires capture-note; the rest remain greyed placeholders.
    expect(screen.getByRole("button", { name: "Capture note" })).toBeEnabled();
    expect(screen.getByRole("button", { name: "Daily brief" })).toBeDisabled();
    const disabled = slots.filter((slot) => slot.hasAttribute("disabled"));
    expect(disabled).toHaveLength(7);
  });

  it("exposes the persistent global Ask-Heimlich launcher (enabled)", () => {
    renderShell();
    expect(screen.getByLabelText("Ask Heimlich or type a command")).toBeEnabled();
  });
});

describe("DashboardShell config-driven content (one view, four modes, no per-mode conditional)", () => {
  it("populates Developer mode from its config and region data", () => {
    renderShell("mode.developer.ready");
    expect(screen.getByText("VS Code")).toBeInTheDocument();
    expect(screen.getByText("Ready to build.")).toBeInTheDocument();
    expect(screen.getByText("dev · checks passing")).toBeInTheDocument();
    expect(screen.getByText("cerebral-helm")).toBeInTheDocument();
    expect(screen.getByText("Team standup")).toBeInTheDocument();
    expect(screen.getByText(/TypeScript 5.9/)).toBeInTheDocument();
  });

  it("renders Executive purely from config — no Developer content leaks", () => {
    renderShell("mode.executive.ready");
    expect(screen.getByText("Chrome")).toBeInTheDocument();
    expect(screen.getByText("Good day.")).toBeInTheDocument();
    expect(screen.getByText("Market Brief")).toBeInTheDocument();
    expect(screen.getByText("Markets up modestly")).toBeInTheDocument();
    expect(screen.queryByText("VS Code")).toBeNull();
    expect(screen.queryByText("Ready to build.")).toBeNull();
  });

  it("renders a threshold-tinted battery bar when a charge percentage is available", () => {
    // Developer mocks a 47% battery — the health panel shows the percentage (bottom bar too).
    renderShell("mode.developer.ready");
    const information = screen.getByRole("complementary", { name: "Information" });
    expect(within(information).getByText("47%")).toBeInTheDocument();
  });

  it("still renders an honest battery-unavailable metric when no percentage is delivered", () => {
    // The agent-expanded fixture keeps battery honestly unavailable while system health is live.
    renderShell("agent.research-analyst.expanded");
    const information = screen.getByRole("complementary", { name: "Information" });
    expect(within(information).getByTitle(/Battery — requires the macOS host/)).toHaveTextContent("Unavailable");
  });
});

describe("DashboardShell mode switching (D2)", () => {
  it("switches mode on click via applyMode — re-themes and re-populates without remounting", () => {
    renderShell(); // Executive default
    expect(screen.getByText("Chrome")).toBeInTheDocument();
    expect(selectedModeButton()).toHaveTextContent("Executive");

    fireEvent.click(screen.getByRole("button", { name: "Developer" }));

    expect(selectedModeButton()).toHaveTextContent("Developer");
    expect(screen.getByText("VS Code")).toBeInTheDocument();
    expect(screen.getByText("Ready to build.")).toBeInTheDocument();
    expect(screen.queryByText("Chrome")).toBeNull();
  });
});

describe("DashboardShell command surfaces (D3 / NIC-58)", () => {
  it("opens a Heimlich conversation from the launcher and continues from the docked input", () => {
    renderShell();
    const launcher = screen.getByLabelText("Ask Heimlich or type a command");

    fireEvent.change(launcher, { target: { value: "what's on today?" } });
    fireEvent.keyDown(launcher, { key: "Enter" });

    const dialog = screen.getByRole("dialog", { name: "Heimlich conversation" });
    expect(within(dialog).getByText("what's on today?")).toBeInTheDocument();

    const docked = within(dialog).getByLabelText("Continue the conversation");
    fireEvent.change(docked, { target: { value: "and tomorrow?" } });
    fireEvent.keyDown(docked, { key: "Enter" });
    expect(within(dialog).getByText("and tomorrow?")).toBeInTheDocument();

    fireEvent.click(within(dialog).getByRole("button", { name: "Minimize" }));
    expect(screen.queryByRole("dialog", { name: "Heimlich conversation" })).toBeNull();
  });

  it("offers capability-aware suggestions — unavailable actions are visibly disabled", () => {
    renderShell();
    fireEvent.focus(screen.getByLabelText("Ask Heimlich or type a command"));

    expect(screen.getByRole("button", { name: /Ask Heimlich/ })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Capture a note/ })).toBeEnabled();
    expect(screen.getByRole("button", { name: /Open an app/ })).toBeDisabled();
  });
});

describe("DashboardShell persistent bottom bar (D6 / NIC-59)", () => {
  function statusBar() {
    return within(screen.getByRole("contentinfo", { name: "Status bar" }));
  }

  it("shows Heimlich state, the mode, and glanceable weather + battery (CPU/mem/net live in the widget)", () => {
    const { container } = renderShell(); // Executive ready
    const bar = statusBar();
    expect(bar.getByText("Heimlich")).toBeInTheDocument();
    expect(bar.getByText("Idle")).toBeInTheDocument();
    expect(bar.getByText("Executive")).toBeInTheDocument();
    // Executive mocks 72°F Partly Cloudy weather (shown as icon + temperature) and an 82% battery.
    expect(bar.getByText("72°F")).toBeInTheDocument();
    expect(bar.getByLabelText("Battery 82%")).toBeInTheDocument();
    // The clock is present but its value is masked in visual snapshots (determinism).
    expect(container.querySelector(".bottom-bar__clock")).not.toBeNull();
    // Detailed CPU/memory/network metrics moved out of the bar into the System Health widget.
    expect(bar.queryByText(/CPU/)).toBeNull();
    expect(bar.queryByText(/Wi-Fi/)).toBeNull();
  });

  it("tints the mode label with the active mode accent (home dashboard only)", () => {
    const { container } = renderShell();
    expect(container.querySelector(".bottom-bar__mode")).toHaveTextContent("Executive");
  });

  it("keeps Settings honest-disabled and no longer surfaces Emergency", () => {
    renderShell();
    const bar = statusBar();
    expect(bar.getByRole("button", { name: "Settings" })).toBeDisabled();
    expect(bar.queryByRole("button", { name: "Emergency" })).toBeNull();
  });

  it("shows honest-unavailable weather and battery when the dashboard is offline", () => {
    renderShell("failure.dashboard_offline");
    const bar = statusBar();
    expect(bar.getByText("Weather · Unavailable")).toBeInTheDocument();
    expect(bar.getByText("Battery · Unavailable")).toBeInTheDocument();
  });
});

describe("DashboardShell confirmation surface (D5 / NIC-62)", () => {
  function renderWithConfirmation() {
    const rendered = renderShell();
    act(() => rendered.bridge.replayConfirmation());
    return rendered;
  }

  it("discloses the exact action in full when a confirmation arrives", () => {
    renderWithConfirmation();
    const dialog = screen.getByRole("dialog", { name: "Confirm action" });
    expect(within(dialog).getByText("Run allowlisted hook ondraft-dev.")).toBeInTheDocument();
    expect(within(dialog).getByText("hook.run v1.0.0 — Execute a configured allowlisted hook without accepting arbitrary shell text.")).toBeInTheDocument();
    // The explicit "nothing has happened yet" statement is always present (design spec §9).
    expect(within(dialog).getByText("Execution has not happened yet.")).toBeInTheDocument();
  });

  it("does not default-focus Approve — the safe Review/Cancel choice is focused (contract)", () => {
    renderWithConfirmation();
    // The canonical fixture's defaultFocusedChoice is "review".
    expect(screen.getByRole("button", { name: "Review" })).toHaveFocus();
    expect(screen.getByRole("button", { name: "Approve" })).not.toHaveFocus();
  });

  it("submits the decision via the bridge and the surface clears (never UI-local)", () => {
    renderWithConfirmation();
    fireEvent.click(screen.getByRole("button", { name: "Approve" }));
    expect(screen.queryByRole("dialog", { name: "Confirm action" })).toBeNull();
  });

  it("cancels on Escape", () => {
    renderWithConfirmation();
    fireEvent.keyDown(screen.getByRole("dialog", { name: "Confirm action" }), { key: "Escape" });
    expect(screen.queryByRole("dialog", { name: "Confirm action" })).toBeNull();
  });

  it("reveals technical detail (plan hash) only after Review is pressed", () => {
    renderWithConfirmation();
    const dialog = screen.getByRole("dialog", { name: "Confirm action" });
    expect(within(dialog).queryByText(/sha256:/)).toBeNull();
    fireEvent.click(within(dialog).getByRole("button", { name: "Review" }));
    expect(within(dialog).getByText(/sha256:/)).toBeInTheDocument();
  });
});

describe("DashboardShell degraded states (E4 / NIC-64)", () => {
  it("first-paint loading shows a skeleton, never a blank screen, and hides the live rails", () => {
    renderShell("system.dashboard.loading");
    expect(screen.getByText("Loading your dashboard…")).toBeInTheDocument();
    // The populated three-zone rails are not mounted while loading — the skeleton stands in.
    expect(screen.queryByRole("complementary", { name: "Information" })).toBeNull();
    expect(screen.queryByRole("group", { name: "Mode" })).toBeNull();
  });

  it("offline shows a specific recovery banner and suppresses every mutating control (AC #3)", () => {
    renderShell("failure.dashboard_offline");
    const banner = screen.getByRole("status");
    expect(within(banner).getByText("Dashboard is offline")).toBeInTheDocument();
    expect(within(banner).getByRole("button", { name: "Retry connection" })).toBeInTheDocument();

    // Mode switch, quick actions, and the command launcher are all read-only.
    for (const option of within(screen.getByRole("group", { name: "Mode" })).getAllByRole("button")) {
      expect(option).toBeDisabled();
    }
    for (const slot of within(screen.getByRole("group", { name: "Quick actions" })).getAllByRole("button")) {
      expect(slot).toBeDisabled();
    }
    expect(screen.getByLabelText("Ask Heimlich or type a command")).toBeDisabled();
  });

  it("error shows a specific top-level banner while keeping last-known data visible", () => {
    renderShell("failure.dashboard_error");
    const banner = screen.getByRole("status");
    expect(within(banner).getByText("Something went wrong")).toBeInTheDocument();
    // Not blank: the last-known stale git widget is still shown.
    expect(screen.getByText("dev · last known")).toBeInTheDocument();
  });

  it("folds a bridge read-only recovery event into a recovery banner and read-only controls", () => {
    const { bridge } = renderShell();
    expect(screen.queryByText("Read-only recovery")).toBeNull();

    act(() =>
      bridge.emit({
        eventId: "brevt_test_recovery",
        type: "system.status.changed",
        schemaVersion: "1.0.0",
        timestamp: "2026-06-23T16:29:00.000Z",
        payload: {
          category: "bridge_failure",
          state: { startupMode: "recovery", status: "read_only", message: "Bridge major version is incompatible." }
        }
      })
    );

    expect(screen.getByText("Read-only recovery")).toBeInTheDocument();
    expect(screen.getByText("Bridge major version is incompatible.")).toBeInTheDocument();
    expect(within(screen.getByRole("group", { name: "Mode" })).getAllByRole("button")[0]).toBeDisabled();
  });

  it("renders a resolved-but-empty region as a calm empty state, distinct from unavailable", () => {
    renderShellWithState((base) => ({
      ...base,
      regions: {
        ...base.regions,
        news: { state: "empty", headlines: [], emptyMessage: "No headlines right now" }
      }
    }));
    const empty = screen.getByText("No headlines right now");
    // Empty is NOT the dashed/disabled unavailable treatment.
    expect(empty).toHaveClass("empty-state");
    expect(empty).not.toHaveAttribute("aria-disabled");
  });

  it("renders an unavailable region as the honest disabled treatment (not an empty state)", () => {
    renderShellWithState((base) => ({
      ...base,
      regions: {
        ...base.regions,
        news: { state: "unavailable", headlines: [], emptyMessage: "News is unavailable" }
      }
    }));
    const unavailable = screen.getByText("News is unavailable");
    expect(unavailable).toHaveClass("unavailable");
    expect(unavailable).toHaveAttribute("aria-disabled", "true");
  });
});

describe("DashboardShell quick actions (D4 / NIC-117 b)", () => {
  it("dispatches the wired capture-note action and surfaces an honest acknowledgement", async () => {
    renderShell();

    fireEvent.click(screen.getByRole("button", { name: "Capture note" }));

    // The real bridge op runs; the returned note id is reported (never a fabricated outcome).
    const dialog = await screen.findByRole("dialog", { name: "Heimlich conversation" });
    expect(within(dialog).getByText(/Captured a quick note \(note_/)).toBeInTheDocument();
  });
});
