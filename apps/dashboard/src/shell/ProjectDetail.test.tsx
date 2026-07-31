import type { ComponentProps } from "react";
import { render, screen, fireEvent } from "@testing-library/react";
import { describe, it, expect, vi } from "vitest";
import { ProjectDetail } from "./ProjectDetail";

/** NIC-129: the project detail view renders a project's PROJECT.md as markdown plus a
 *  placeholder live-status section, an editable priority stepper, and closes through the
 *  injected onClose callback. */

const body = "# CerebralHelm\n\nA **local-first** desktop.\n\n## Focus\n\n- Ship the widget";

function renderDetail(props: Partial<ComponentProps<typeof ProjectDetail>> = {}) {
  const onClose = vi.fn();
  const onSetImportance = vi.fn();
  render(
    <ProjectDetail
      name={props.name ?? "CerebralHelm"}
      markdownBody={props.markdownBody ?? body}
      importance={props.importance ?? 5}
      onClose={props.onClose ?? onClose}
      onSetImportance={props.onSetImportance ?? onSetImportance}
    />
  );
  return { onClose, onSetImportance };
}

describe("ProjectDetail (NIC-129)", () => {
  it("renders the project name and its markdown body", () => {
    renderDetail();
    expect(screen.getByRole("main", { name: "Project: CerebralHelm" })).toBeTruthy();
    expect(screen.getByText("local-first").tagName).toBe("STRONG");
    expect(screen.getByText("Ship the widget").tagName).toBe("LI");
  });

  it("shows the live-status placeholder section", () => {
    renderDetail({ markdownBody: "" });
    expect(screen.getByRole("region", { name: "Live status" })).toBeTruthy();
    expect(screen.getByText(/coming soon/i)).toBeTruthy();
  });

  it("calls onClose when the × is clicked", () => {
    const { onClose } = renderDetail();
    fireEvent.click(screen.getByRole("button", { name: "Close" }));
    expect(onClose).toHaveBeenCalledOnce();
  });

  it("shows the current priority and reports increments/decrements", () => {
    const { onSetImportance } = renderDetail({ importance: 6 });
    expect(screen.getByLabelText("Priority").textContent).toContain("6");

    fireEvent.click(screen.getByRole("button", { name: "Increase priority" }));
    expect(screen.getByLabelText("Priority").textContent).toContain("7");
    expect(onSetImportance).toHaveBeenLastCalledWith(7);

    fireEvent.click(screen.getByRole("button", { name: "Decrease priority" }));
    expect(onSetImportance).toHaveBeenLastCalledWith(6);
  });

  it("floors priority at 0 — decrement is disabled and reports nothing", () => {
    const { onSetImportance } = renderDetail({ importance: 0 });
    const decrement = screen.getByRole("button", { name: "Decrease priority" }) as HTMLButtonElement;
    expect(decrement.disabled).toBe(true);
    fireEvent.click(decrement);
    expect(onSetImportance).not.toHaveBeenCalled();
  });
});
