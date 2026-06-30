import { render, screen, within } from "@testing-library/react";
import { DashboardShell } from "./DashboardShell";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { ThemeProvider } from "../app/ThemeProvider";
import { createBootstrapStore } from "../state/bootstrapStore";

function renderShell() {
  return render(
    <DashboardStateProvider store={createBootstrapStore()}>
      <ThemeProvider>
        <DashboardShell />
      </ThemeProvider>
    </DashboardStateProvider>
  );
}

describe("DashboardShell", () => {
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

    const group = screen.getByRole("group", { name: "Mode" });
    const options = within(group).getAllByRole("button");
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

  it("renders exactly eight quick-action slots, all disabled honest placeholders", () => {
    renderShell();

    const grid = screen.getByRole("group", { name: "Quick actions" });
    const slots = within(grid).getAllByRole("button");
    expect(slots).toHaveLength(8);
    expect(slots.every((slot) => slot.hasAttribute("disabled"))).toBe(true);
  });

  it("exposes the persistent global launcher as a disabled, labelled input", () => {
    renderShell();

    const launcher = screen.getByLabelText("Ask Heimlich or type a command");
    expect(launcher).toBeDisabled();
  });
});
