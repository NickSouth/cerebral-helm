import { render, screen } from "@testing-library/react";
import { App } from "./App";

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
});
