import { render, screen, fireEvent } from "@testing-library/react";
import { vi } from "vitest";
import { SidebarApp } from "./SidebarApp";

/**
 * The left-edge sidebar surface: the dashboard's own controls in one narrow column, so Heimlich
 * is reachable from inside a fullscreen app.
 *
 * The contract these tests hold is *reuse*: the sidebar must expose the same command locus, mode
 * switcher, quick actions, schedule, quick apps and agent roster the dashboard does — not a
 * reduced second control surface (that is the companion's job) and not a fork.
 */
describe("SidebarApp (?surface=sidebar)", () => {
  it("renders the shared control set in one column", () => {
    render(<SidebarApp />);

    expect(screen.getByRole("complementary", { name: /sidebar$/ })).toBeInTheDocument();

    // The command locus — the same CommandSurface the dashboard's launcher uses.
    expect(screen.getByRole("combobox", { name: "Type a command" })).toBeInTheDocument();

    // The shared mode switcher (extracted from the right rail) with its four controls.
    const modeGroup = screen.getByRole("group", { name: "Mode" });
    expect(modeGroup).toBeInTheDocument();

    // Operational surfaces carried over from the rails and the centre stage. The panel
    // primitive labels itself with an eyebrow rather than an ARIA region, so assert the label.
    expect(screen.getByRole("group", { name: "Quick actions" })).toBeInTheDocument();
    expect(screen.getByText("Today")).toBeInTheDocument();
    expect(screen.getByText("Quick Apps")).toBeInTheDocument();
    expect(screen.getByText("Agents")).toBeInTheDocument();
  });

  it("keeps the window controls native-only, so the surface still renders in a browser", () => {
    // No `webkit.messageHandlers.sidebarControl` exists here; pressing Hide must be a no-op
    // rather than throwing, so the surface stays usable for design work and tests.
    render(<SidebarApp />);

    fireEvent.click(screen.getByRole("button", { name: "Hide the sidebar" }));

    expect(screen.getByRole("complementary", { name: /sidebar$/ })).toBeInTheDocument();
  });

  it("hands Report and Input quick actions to the dashboard instead of opening them inline", () => {
    const postMessage = vi.fn();
    (window as unknown as { webkit?: unknown }).webkit = {
      messageHandlers: { sidebarControl: { postMessage } }
    };
    render(<SidebarApp />);

    // "Daily brief" is a Report action. In the column it must NOT render a report region — it
    // reveals the dashboard and opens there (the column is too narrow to read one in).
    fireEvent.click(screen.getByRole("button", { name: "Daily brief" }));

    expect(postMessage).toHaveBeenCalledWith(
      expect.objectContaining({ action: "revealDashboard", report: "daily-brief" })
    );
    expect(screen.queryByRole("region", { name: /report$/ })).toBeNull();

    delete (window as unknown as { webkit?: unknown }).webkit;
  });

  it("toggles the pin control's pressed state", () => {
    render(<SidebarApp />);

    const pin = screen.getByRole("button", { name: "Keep the sidebar open" });
    expect(pin).toHaveAttribute("aria-pressed", "false");

    fireEvent.click(pin);

    expect(screen.getByRole("button", { name: "Unpin the sidebar" })).toHaveAttribute(
      "aria-pressed",
      "true"
    );
  });
});
