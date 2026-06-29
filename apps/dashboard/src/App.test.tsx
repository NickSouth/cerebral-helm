import { render, screen } from "@testing-library/react";
import { App } from "./App";
import { dashboardStoryFixtures } from "./fixtures/canonicalFixtures";

describe("App", () => {
  it("renders the token reference page", () => {
    render(<App />);

    expect(screen.getByRole("heading", { level: 1, name: "Token reference" })).toBeInTheDocument();
  });

  it("renders every mode palette through data-mode, not a per-mode conditional", () => {
    const { container } = render(<App />);

    for (const mode of ["executive", "developer", "school", "entertainment"]) {
      expect(container.querySelector(`[data-mode="${mode}"]`)).not.toBeNull();
    }
  });

  it("shows an honest-unavailable surface for unwired capability", () => {
    render(<App />);

    expect(screen.getByText("Not implemented")).toHaveAttribute("aria-disabled", "true");
  });

  it("exposes dashboard story states from the canonical fixture catalog", () => {
    expect(dashboardStoryFixtures.map((fixture) => fixture.canonicalKey)).toEqual(
      expect.arrayContaining(["mode.developer.ready", "failure.dashboard_offline"])
    );
  });
});
