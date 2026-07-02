import { render, screen } from "@testing-library/react";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { AppRoot } from "./AppRoot";
import { useDashboardState } from "../state/DashboardStateProvider";
import { Unavailable } from "../components/Unavailable";
import { toModeId } from "../tokens/tokens";

const here = path.dirname(fileURLToPath(import.meta.url));
const responsiveCss = readFileSync(path.join(here, "..", "styles", "responsive.css"), "utf8");

describe("app architecture", () => {
  it("applies the active mode from bootstrap state via data-mode (no per-component conditional)", () => {
    const { container } = render(<AppRoot />);

    // Executive is the default mode (ADR-007).
    expect(container.querySelector('.app-root[data-mode="executive"]')).not.toBeNull();
  });

  it("renders a skip link targeting the main region", () => {
    render(<AppRoot />);

    const skip = screen.getByRole("link", { name: /skip to main content/i });
    expect(skip).toHaveAttribute("href", "#main");
    expect(document.getElementById("main")).not.toBeNull();
  });

  it("maps dashboard modes to lowercase token ids and rejects unknown modes", () => {
    expect(toModeId("Developer")).toBe("developer");
    expect(toModeId("Executive")).toBe("executive");
    expect(() => toModeId("Holiday")).toThrow(/Unknown dashboard mode/);
  });

  it("renders an accessible honest-unavailable surface", () => {
    render(<Unavailable label="Battery" />);

    expect(screen.getByText("Battery")).toHaveAttribute("aria-disabled", "true");
  });

  it("requires the state-boundary provider (no silent default)", () => {
    function Consumer() {
      useDashboardState();
      return null;
    }

    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    expect(() => render(<Consumer />)).toThrow(/DashboardStateProvider/);
    errorSpy.mockRestore();
  });

  it("defines responsive breakpoint tokens and an external content cap", () => {
    expect(responsiveCss).toMatch(/--ch-breakpoint-compact:/);
    expect(responsiveCss).toMatch(/--ch-breakpoint-external:/);
    expect(responsiveCss).toMatch(/min-width:\s*1920px/);
  });
});
