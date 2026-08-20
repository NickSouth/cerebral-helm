import type { ComponentProps } from "react";
import { render, screen, fireEvent } from "@testing-library/react";
import { describe, it, expect, vi } from "vitest";
import { ProjectDetail } from "./ProjectDetail";

// The cycle section fetches through the bridge and has its own suite; stubbed here so these tests
// stay about the detail view's own chrome.
vi.mock("./ProjectCycleSection", () => ({
  ProjectCycleSection: ({ linearProject }: { linearProject: string | null }) => (
    <div data-testid="cycle-section">{linearProject ?? "unlinked"}</div>
  )
}));

/** NIC-129 + NIC-221: the project detail view renders a project's PROJECT.md as markdown, an
 *  editable priority stepper, and — where the "Live status" placeholder used to be — the live
 *  Linear cycle section, all in ONE scroll (the approved stacked layout). */

const body = "# CerebralHelm\n\nA **local-first** desktop.\n\n## Focus\n\n- Ship the widget";

function renderDetail(props: Partial<ComponentProps<typeof ProjectDetail>> = {}) {
  const onClose = vi.fn();
  const onSetImportance = vi.fn();
  const { container } = render(
    <ProjectDetail
      name={props.name ?? "CerebralHelm"}
      markdownBody={props.markdownBody ?? body}
      importance={props.importance ?? 5}
      // `??` would swallow an explicit null — and null is the state under test (unlinked), not a
      // missing argument. Only `undefined` means "the caller didn't say".
      linearProject={props.linearProject === undefined ? "CerebralHelm" : props.linearProject}
      onClose={props.onClose ?? onClose}
      onSetImportance={props.onSetImportance ?? onSetImportance}
    />
  );
  return { onClose, onSetImportance, container };
}

describe("ProjectDetail (NIC-129)", () => {
  it("renders the project name and its markdown body", () => {
    renderDetail();
    expect(screen.getByRole("main", { name: "Project: CerebralHelm" })).toBeTruthy();
    expect(screen.getByText("local-first").tagName).toBe("STRONG");
    expect(screen.getByText("Ship the widget").tagName).toBe("LI");
  });

  it("renders the Linear cycle section where the placeholder used to be (NIC-221)", () => {
    renderDetail({ markdownBody: "" });
    // The old "Live status ... coming soon" placeholder is gone for good; anything still asserting
    // it would be asserting a promise the app no longer makes.
    expect(screen.queryByText(/coming soon/i)).toBeNull();
    expect(screen.getByTestId("cycle-section").textContent).toBe("CerebralHelm");
  });

  it("passes an unlinked project through as null rather than hiding the section", () => {
    renderDetail({ linearProject: null });
    expect(screen.getByTestId("cycle-section").textContent).toBe("unlinked");
  });

  it("puts the brief and the cycle in one scroll container (stacked layout)", () => {
    const { container } = renderDetail();
    const scroll = container.querySelector(".project-detail__scroll");
    expect(scroll).toBeTruthy();
    // Both live inside it — that single container IS the stacked layout, and it is what the
    // cycle's sticky headers stick to.
    expect(scroll?.querySelector(".project-detail__body")).toBeTruthy();
    expect(scroll?.querySelector("[data-testid='cycle-section']")).toBeTruthy();
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
