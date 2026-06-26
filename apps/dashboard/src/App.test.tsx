import { render, screen } from "@testing-library/react";
import { App } from "./App";
import { dashboardStoryFixtures } from "./fixtures/canonicalFixtures";

describe("App", () => {
  it("renders the mock bridge bootstrap state", () => {
    render(<App />);

    expect(
      screen.getByRole("heading", {
        name: "CerebralHelm is running as a local-first workspace."
      })
    ).toBeInTheDocument();
    expect(screen.getByText("Developer")).toBeInTheDocument();
    expect(screen.getByText("NIC-12 Workspace Bootstrap")).toBeInTheDocument();
  });

  it("exposes dashboard story states from the canonical fixture catalog", () => {
    expect(dashboardStoryFixtures.map((fixture) => fixture.canonicalKey)).toEqual(
      expect.arrayContaining(["mode.developer.ready", "failure.dashboard_offline"])
    );
  });
});
