import { render, screen, within, fireEvent } from "@testing-library/react";
import { DashboardShell } from "./DashboardShell";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { BridgeProvider } from "../state/BridgeProvider";
import { ThemeProvider } from "../app/ThemeProvider";
import { createBridgeStore } from "../state/bridgeStore";
import { createMockCerebralBridge, loadBootstrapState } from "../bridge/mockCerebralBridge";
import { getDashboardConfigBundle, getDashboardFixture } from "../fixtures/canonicalFixtures";

/** Render the shell over a bridge-backed store. With no key, boots the default mode (Executive). */
function renderShell(canonicalKey?: string) {
  const bridge = canonicalKey ? createMockCerebralBridge({ bootstrapKey: canonicalKey }) : createMockCerebralBridge();
  const initial = canonicalKey ? { ...getDashboardConfigBundle(), ...getDashboardFixture(canonicalKey) } : loadBootstrapState();
  const store = createBridgeStore(bridge, initial);
  return render(
    <BridgeProvider bridge={bridge}>
      <DashboardStateProvider store={store}>
        <ThemeProvider>
          <DashboardShell />
        </ThemeProvider>
      </DashboardStateProvider>
    </BridgeProvider>
  );
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

  it("renders eight quick-action slots, all disabled, with config labels", () => {
    renderShell();
    const slots = within(screen.getByRole("group", { name: "Quick actions" })).getAllByRole("button");
    expect(slots).toHaveLength(8);
    expect(slots.every((slot) => slot.hasAttribute("disabled"))).toBe(true);
    expect(screen.getByRole("button", { name: "Daily brief" })).toBeDisabled();
  });

  it("exposes the persistent global launcher as a disabled, labelled input", () => {
    renderShell();
    expect(screen.getByLabelText("Ask Heimlich or type a command")).toBeDisabled();
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

  it("renders an honest battery-unavailable metric pre-Mac", () => {
    renderShell("mode.developer.ready");
    expect(screen.getByTitle(/Battery — requires the macOS host/)).toHaveTextContent("Unavailable");
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
