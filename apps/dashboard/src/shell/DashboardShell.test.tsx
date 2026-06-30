import { render, screen, within } from "@testing-library/react";
import { DashboardShell } from "./DashboardShell";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { ThemeProvider } from "../app/ThemeProvider";
import { createBootstrapStore } from "../state/bootstrapStore";
import { createBridgeStore } from "../state/bridgeStore";
import { createMockCerebralBridge } from "../bridge/mockCerebralBridge";
import { getDashboardConfigBundle, getDashboardFixture } from "../fixtures/canonicalFixtures";

function renderShell() {
  return render(
    <DashboardStateProvider store={createBootstrapStore()}>
      <ThemeProvider>
        <DashboardShell />
      </ThemeProvider>
    </DashboardStateProvider>
  );
}

/** Render the shell seeded from a specific canonical mode fixture (the same view, no fork). */
function renderMode(canonicalKey: string) {
  const initial = { ...getDashboardConfigBundle(), ...getDashboardFixture(canonicalKey) };
  const store = createBridgeStore(createMockCerebralBridge({ bootstrapKey: canonicalKey }), initial);
  return render(
    <DashboardStateProvider store={store}>
      <ThemeProvider>
        <DashboardShell />
      </ThemeProvider>
    </DashboardStateProvider>
  );
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

  it("renders four mode controls with exactly one selected (the active mode)", () => {
    renderShell();
    const options = within(screen.getByRole("group", { name: "Mode" })).getAllByRole("button");
    expect(options).toHaveLength(4);
    const selected = options.filter((option) => option.getAttribute("aria-pressed") === "true");
    expect(selected).toHaveLength(1);
    expect(selected[0]).toHaveTextContent("Developer");
  });

  it("renders the fixed four-agent roster", () => {
    renderShell();
    for (const name of ["Research Analyst", "Financial Advisor", "Project Manager", "System Janitor"]) {
      expect(screen.getByText(name)).toBeInTheDocument();
    }
  });

  it("renders eight quick-action slots, all disabled, with config labels", () => {
    renderShell();
    const slots = within(screen.getByRole("group", { name: "Quick actions" })).getAllByRole("button");
    expect(slots).toHaveLength(8);
    expect(slots.every((slot) => slot.hasAttribute("disabled"))).toBe(true);
    expect(screen.getByRole("button", { name: "Run tests" })).toBeDisabled();
  });

  it("exposes the persistent global launcher as a disabled, labelled input", () => {
    renderShell();
    expect(screen.getByLabelText("Ask Heimlich or type a command")).toBeDisabled();
  });
});

describe("DashboardShell config-driven content (one view, four modes, no per-mode conditional)", () => {
  it("populates Developer mode from its config and region data", () => {
    renderMode("mode.developer.ready");
    expect(screen.getByText("VS Code")).toBeInTheDocument();
    expect(screen.getByText("Ready to build.")).toBeInTheDocument(); // greeting
    expect(screen.getByText("dev · checks passing")).toBeInTheDocument(); // left widget headline
    expect(screen.getByText("cerebral-helm")).toBeInTheDocument(); // right widget (repositories)
    expect(screen.getByText("Team standup")).toBeInTheDocument(); // schedule
    expect(screen.getByText(/TypeScript 5.9/)).toBeInTheDocument(); // news
  });

  it("renders a different mode purely from config (Executive) — no Developer content leaks", () => {
    renderMode("mode.executive.ready");
    expect(screen.getByText("Chrome")).toBeInTheDocument();
    expect(screen.getByText("Good day.")).toBeInTheDocument();
    expect(screen.getByText("Market Brief")).toBeInTheDocument(); // left widget label
    expect(screen.getByText("Markets up modestly")).toBeInTheDocument();
    // The shell is one composition: Developer-only content must not appear in Executive.
    expect(screen.queryByText("VS Code")).toBeNull();
    expect(screen.queryByText("Ready to build.")).toBeNull();
  });

  it("renders an honest battery-unavailable metric pre-Mac", () => {
    renderMode("mode.developer.ready");
    const battery = screen.getByTitle(/Battery — requires the macOS host/);
    expect(battery).toHaveTextContent("Unavailable");
  });
});
