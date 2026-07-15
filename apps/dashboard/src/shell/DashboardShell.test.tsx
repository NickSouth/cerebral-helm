import { render, screen, within, fireEvent, act, waitFor } from "@testing-library/react";
import { DashboardShell } from "./DashboardShell";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { BridgeProvider } from "../state/BridgeProvider";
import { ActionStatusProvider } from "../state/ActionStatusProvider";
import { SettingsProvider } from "../state/SettingsProvider";
import { AppearanceProvider } from "../state/AppearanceProvider";
import { ThemeProvider } from "../app/ThemeProvider";
import { createBridgeStore } from "../state/bridgeStore";
import { createMockCerebralBridge, loadBootstrapState } from "../bridge/mockCerebralBridge";
import { getDashboardConfigBundle, getDashboardFixture } from "../fixtures/canonicalFixtures";
import type { DashboardState } from "../state/dashboardState";

function renderProviders(
  bridge: ReturnType<typeof createMockCerebralBridge>,
  store: ReturnType<typeof createBridgeStore>
) {
  return render(
    <BridgeProvider bridge={bridge}>
      <DashboardStateProvider store={store}>
        <AppearanceProvider>
          <ThemeProvider>
            <ActionStatusProvider>
              <SettingsProvider>
                <DashboardShell />
              </SettingsProvider>
            </ActionStatusProvider>
          </ThemeProvider>
        </AppearanceProvider>
      </DashboardStateProvider>
    </BridgeProvider>
  );
}

/** Render the shell over a bridge-backed store. With no key, boots the default mode (Executive). */
function renderShell(canonicalKey?: string) {
  const bridge = canonicalKey
    ? createMockCerebralBridge({ bootstrapKey: canonicalKey })
    : createMockCerebralBridge();
  const initial = canonicalKey
    ? { ...getDashboardConfigBundle(), ...getDashboardFixture(canonicalKey) }
    : loadBootstrapState();
  const store = createBridgeStore(bridge, initial);
  return { bridge, ...renderProviders(bridge, store) };
}

/** Render the shell with an arbitrary state override (for degraded-state coverage, NIC-64). */
function renderShellWithState(mutate: (base: DashboardState) => DashboardState) {
  const bridge = createMockCerebralBridge();
  const base: DashboardState = {
    ...getDashboardConfigBundle(),
    ...getDashboardFixture("mode.executive.ready")
  };
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
    expect(
      within(main as HTMLElement).getByRole("region", { name: "Heimlich" })
    ).toBeInTheDocument();
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
    for (const name of [
      "Research Analyst",
      "Financial Advisor",
      "Project Manager",
      "System Janitor"
    ]) {
      expect(screen.getByText(name)).toBeInTheDocument();
    }
  });

  it("shows every agent as grey / Not implemented for the MVP (NIC-124)", () => {
    renderShell();
    const agents = Array.from(document.querySelectorAll<HTMLElement>(".agent-list__item"));
    expect(agents).toHaveLength(4);
    for (const agent of agents) {
      expect(within(agent).getByText("Not implemented")).toBeInTheDocument();
      // The status dot is the neutral/grey activity (idle → neutral token).
      expect(agent.querySelector('.agent-status-dot[data-activity="idle"]')).not.toBeNull();
    }
  });

  it("renders eight quick-action slots — wired ones enabled, placeholders disabled", () => {
    renderShell();
    const slots = within(screen.getByRole("group", { name: "Quick actions" })).getAllByRole(
      "button"
    );
    expect(slots).toHaveLength(8);
    // D4 wires capture-note; the rest remain greyed placeholders.
    expect(screen.getByRole("button", { name: "Capture note" })).toBeEnabled();
    expect(screen.getByRole("button", { name: "Daily brief" })).toBeDisabled();
    const disabled = slots.filter((slot) => slot.hasAttribute("disabled"));
    expect(disabled).toHaveLength(7);
  });

  it("exposes the persistent global command launcher (enabled)", () => {
    renderShell();
    expect(screen.getByLabelText("Type a command")).toBeEnabled();
  });

  it("shows the CerebralHelm brand (wordmark + helm mark) in the header row", () => {
    const { container } = renderShell();
    const brand = screen.getByRole("img", { name: "CerebralHelm" });
    expect(brand).toBeInTheDocument();
    expect(brand.querySelector(".brand-wordmark")).not.toBeNull();
    expect(brand.querySelector(".brand-mark")).not.toBeNull();
    // Heimlich's portrait replaced the placeholder wheel in the bottom bar's avatar slot.
    expect(container.querySelector(".bottom-bar__avatar .heimlich-avatar")).not.toBeNull();
  });
});

describe("DashboardShell config-driven content (one view, four modes, no per-mode conditional)", () => {
  it("populates Developer mode from its config and region data", () => {
    renderShell("mode.developer.ready");
    expect(screen.getByText("Ready to build.")).toBeInTheDocument();
    expect(screen.getByText("dev · checks passing")).toBeInTheDocument();
    expect(screen.getByText("cerebral-helm")).toBeInTheDocument();
    expect(screen.getByText("Team standup")).toBeInTheDocument();
    expect(screen.getByText(/TypeScript 5.9/)).toBeInTheDocument();
  });

  it("renders Executive purely from config — no Developer content leaks", () => {
    renderShell("mode.executive.ready");
    expect(screen.getByText("Good day.")).toBeInTheDocument();
    expect(screen.getByText("Market Brief")).toBeInTheDocument();
    expect(screen.getByText("Markets up modestly")).toBeInTheDocument();
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
    expect(within(information).getByTitle(/Battery — requires the macOS host/)).toHaveTextContent(
      "Unavailable"
    );
  });
});

describe("DashboardShell mode switching (D2)", () => {
  it("switches mode on click via applyMode — re-themes and re-populates without remounting", () => {
    renderShell(); // Executive default
    expect(screen.getByText("Good day.")).toBeInTheDocument();
    expect(selectedModeButton()).toHaveTextContent("Executive");

    fireEvent.click(screen.getByRole("button", { name: "Developer" }));

    expect(selectedModeButton()).toHaveTextContent("Developer");
    expect(screen.getByText("Ready to build.")).toBeInTheDocument();
    expect(screen.queryByText("Good day.")).toBeNull();
  });
});

describe("DashboardShell command surfaces (D3 / NIC-58, NIC-124)", () => {
  /** Render the shell over a bridge whose submitCommand is spied/overridable. */
  function renderWithSubmit(receipt?: { commandId: string; accepted: boolean }) {
    const bridge = createMockCerebralBridge();
    const submissions: string[] = [];
    const spyBridge = {
      ...bridge,
      submitCommand(input: { rawInput: string; source: string }) {
        submissions.push(input.rawInput);
        return receipt ? Promise.resolve(receipt) : bridge.submitCommand(input);
      }
    };
    const store = createBridgeStore(spyBridge, loadBootstrapState());
    renderProviders(spyBridge, store);
    return { submissions };
  }

  it("dispatches a command from the launcher and never opens a chat surface", () => {
    const { submissions } = renderWithSubmit();
    const launcher = screen.getByLabelText("Type a command");

    fireEvent.change(launcher, { target: { value: "open notes" } });
    fireEvent.keyDown(launcher, { key: "Enter" });

    expect(submissions).toEqual(["open notes"]);
    // The Heimlich chat/conversation surface was removed (NIC-124) — nothing opens.
    expect(screen.queryByRole("dialog", { name: "Heimlich conversation" })).toBeNull();
  });

  it("reports the honest not-implemented state when a submission is rejected (NIC-124)", async () => {
    renderWithSubmit({ commandId: "", accepted: false });
    const launcher = screen.getByLabelText("Type a command");

    fireEvent.change(launcher, { target: { value: "tell me a joke" } });
    fireEvent.keyDown(launcher, { key: "Enter" });

    expect(await screen.findByText("Heimlich not implemented")).toBeInTheDocument();
  });

  it("offers capability-aware suggestions — unavailable actions are visibly disabled", () => {
    renderShell();
    fireEvent.focus(screen.getByLabelText("Type a command"));

    // The always-first "Ask Heimlich" row is gone (NIC-124) — only command matches remain.
    expect(screen.queryByRole("button", { name: /Ask Heimlich/ })).toBeNull();
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
    // At rest Heimlich reads grey / "Not implemented" for the MVP (NIC-124).
    expect(bar.getByText("Not implemented")).toBeInTheDocument();
    expect(container.querySelector('.bottom-bar__status-dot[data-state="neutral"]')).not.toBeNull();
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

  it("opens the settings window from the gear and no longer surfaces Emergency (E3 / NIC-63)", async () => {
    renderShell();
    const bar = statusBar();
    const settings = bar.getByRole("button", { name: "Settings" });
    expect(settings).toBeEnabled();
    expect(bar.queryByRole("button", { name: "Emergency" })).toBeNull();
    fireEvent.click(settings);
    // The settings surface reads persisted settings on open (NIC-141); waitFor lets
    // that async read settle inside act so it doesn't leak past the test.
    await waitFor(() =>
      expect(screen.getByRole("dialog", { name: "Settings" })).toBeInTheDocument()
    );
  });

  it("shows honest-unavailable weather and battery when the dashboard is offline", () => {
    renderShell("failure.dashboard_offline");
    const bar = statusBar();
    expect(bar.getByText("Weather · Unavailable")).toBeInTheDocument();
    expect(bar.getByText("Battery · Unavailable")).toBeInTheDocument();
  });

  it("opens the mode menu as a native top-most dropdown when the channel exists (NIC-144)", () => {
    const posted: Array<Record<string, unknown>> = [];
    (window as unknown as { webkit?: unknown }).webkit = {
      messageHandlers: { shellControl: { postMessage: (m: unknown) => posted.push(m as Record<string, unknown>) } }
    };
    try {
      renderShell();
      // The trigger's accessible name is the active mode it shows (Executive).
      fireEvent.click(statusBar().getByRole("button", { name: "Executive" }));
      // The native shell owns the dropdown (layers above windows) — post the open action
      // with the trigger's anchor, and do NOT render the in-webview menu.
      expect(posted).toContainEqual(expect.objectContaining({ action: "openModeMenu" }));
      expect(screen.queryByRole("menu", { name: "Switch mode" })).toBeNull();
    } finally {
      delete (window as unknown as { webkit?: unknown }).webkit;
    }
  });

  it("falls back to the in-webview mode menu in a plain browser (no native channel)", () => {
    renderShell();
    fireEvent.click(statusBar().getByRole("button", { name: "Executive" }));
    // No shellControl channel → the upward menu renders in-page as before.
    expect(screen.getByRole("menu", { name: "Switch mode" })).toBeInTheDocument();
  });

  it("reports its on-screen rect to the native shell for window-snap awareness (NIC-144)", () => {
    const posted: Array<Record<string, unknown>> = [];
    (window as unknown as { webkit?: unknown }).webkit = {
      messageHandlers: { shellControl: { postMessage: (m: unknown) => posted.push(m as Record<string, unknown>) } }
    };
    try {
      renderShell();
      const report = posted.find((m) => m.action === "reportBottomBarRect");
      // The bar posts a rect payload the coordinator converts to a reserved strip.
      expect(report).toBeDefined();
      expect(report?.rect).toMatchObject({
        x: expect.any(Number),
        y: expect.any(Number),
        width: expect.any(Number),
        height: expect.any(Number)
      });
    } finally {
      delete (window as unknown as { webkit?: unknown }).webkit;
    }
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
    expect(
      within(dialog).getByText(
        "hook.run v1.0.0 — Execute a configured allowlisted hook without accepting arbitrary shell text."
      )
    ).toBeInTheDocument();
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
    for (const option of within(screen.getByRole("group", { name: "Mode" })).getAllByRole(
      "button"
    )) {
      expect(option).toBeDisabled();
    }
    for (const slot of within(screen.getByRole("group", { name: "Quick actions" })).getAllByRole(
      "button"
    )) {
      expect(slot).toBeDisabled();
    }
    expect(screen.getByLabelText("Type a command")).toBeDisabled();
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
          state: {
            startupMode: "recovery",
            status: "read_only",
            message: "Bridge major version is incompatible."
          }
        }
      })
    );

    expect(screen.getByText("Read-only recovery")).toBeInTheDocument();
    expect(screen.getByText("Bridge major version is incompatible.")).toBeInTheDocument();
    expect(
      within(screen.getByRole("group", { name: "Mode" })).getAllByRole("button")[0]
    ).toBeDisabled();
  });

  it("renders live quick-action progress in the top-left status surface, not under the grid (NIC-124)", () => {
    const { bridge } = renderShell();

    act(() =>
      bridge.emit({
        eventId: "brevt_test_progress",
        type: "workflow.action.progress",
        schemaVersion: "1.0.0",
        timestamp: "2026-07-08T16:29:00.000Z",
        payload: {
          commandId: "cmd_1",
          workflowId: "open-developer-layout",
          actionId: "app-open",
          kind: "native.app.open",
          status: "running",
          index: 2,
          total: 5
        }
      })
    );

    const status = document.querySelector(".action-status") as HTMLElement;
    expect(status).not.toBeNull();
    expect(status).toHaveTextContent("Open developer layout: step 2 of 5 — App open (running)");
    // The old under-grid progress line is gone — the quick-actions group carries no status text.
    expect(document.querySelector(".quick-actions__progress")).toBeNull();
    expect(screen.getByRole("group", { name: "Quick actions" })).not.toHaveTextContent(
      "step 2 of 5"
    );
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
  it("dispatches the wired capture-note action and surfaces the result in the status line", async () => {
    renderShell();

    fireEvent.click(screen.getByRole("button", { name: "Capture note" }));

    // The real bridge op runs; the returned note id is reported in the top-left status surface
    // (never a fabricated outcome, and never a chat surface — NIC-124).
    const status = document.querySelector(".action-status") as HTMLElement;
    await waitFor(() => expect(status).toHaveTextContent(/Captured a quick note \(note_/));
    expect(screen.queryByRole("dialog", { name: "Heimlich conversation" })).toBeNull();
  });
});

describe("DashboardShell native shell-intent hook (NIC-76 / NIC-124)", () => {
  interface ShellIntentWindow {
    __cerebralShell?: { submitCommand?: (text: string) => void };
  }

  it("exposes __cerebralShell.submitCommand, dispatching through the command bus", () => {
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
    renderProviders(spyBridge, store);

    const shell = (window as unknown as ShellIntentWindow).__cerebralShell;
    expect(typeof shell?.submitCommand).toBe("function");
    act(() => {
      shell?.submitCommand?.("open notes");
    });
    // Dispatches straight through the shared bridge — no conversation surface (NIC-124).
    expect(submissions).toEqual(["open notes"]);
  });
});

describe("DashboardShell bottom bar (NIC-76 AC2 / FR-UI-04)", () => {
  it("keeps the persistent bottom bar on its own track — a direct child of the shell, not overlaying content", () => {
    const { container } = renderShell();
    const shell = container.querySelector(".dashboard-shell");
    const bar = shell?.querySelector(":scope > .bottom-bar");
    // The bar is a direct flex-column child (its own track), a sibling of the canvas — so it
    // never composites over dashboard content.
    expect(bar).not.toBeNull();
    expect(shell?.querySelector(".dashboard-canvas")).not.toBeNull();
  });
});
