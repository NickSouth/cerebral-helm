import { render, screen } from "@testing-library/react";
import { CompanionApp } from "./CompanionApp";

/**
 * The secondary-display companion surface (owner decision, 2026-07-06): the
 * Heimlich stream + persistent bottom bar only — never a second control surface.
 */
describe("CompanionApp (?surface=companion)", () => {
  it("renders the Heimlich stream and the bottom bar, and nothing that issues commands", () => {
    render(<CompanionApp />);

    // The reduced presence: companion root + bottom bar (clock/status/gear live there).
    expect(screen.getByRole("main", { name: "CerebralHelm companion" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Settings" })).toBeInTheDocument();

    // No command input, no quick apps/actions, no conversation, no agents.
    expect(screen.queryByRole("textbox")).toBeNull();
    expect(screen.queryByText("QUICK APPS")).toBeNull();
    expect(screen.queryByRole("region", { name: "Quick apps" })).toBeNull();
    expect(screen.queryByRole("region", { name: "Agents" })).toBeNull();
  });
});
