import { render, screen, fireEvent } from "@testing-library/react";
import { describe, it, expect } from "vitest";
import { WidgetSlot } from "./WidgetSlot";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { BridgeProvider } from "../state/BridgeProvider";
import { ActionStatusProvider } from "../state/ActionStatusProvider";
import { createBridgeStore } from "../state/bridgeStore";
import { createMockCerebralBridge, loadBootstrapState } from "../bridge/mockCerebralBridge";
import type { DashboardState } from "../state/dashboardState";
import type { WidgetData } from "../widgets/widgetData";

/** NIC-131 Increment 6: the Developer "Repositories" widget renders active repos with their
 *  branch and opens one in the editor on click through the gated project.open path. */

const reposReady: WidgetData = {
  widgetId: "repositories",
  state: "ready",
  headline: "2 repositories",
  freshness: { observedAt: "2026-07-19T16:00:00.000Z", label: "just now" },
  data: {
    items: [
      {
        id: "cerebral-helm",
        name: "cerebral-helm",
        branch: "mvp-polish/integrations",
        path: "/Users/x/Projects/cerebral-helm"
      },
      { id: "notes", name: "notes", path: "/Users/x/Projects/notes" }
    ]
  }
};

function renderSlot(data: WidgetData, mutate?: (base: DashboardState) => DashboardState) {
  const bridge = createMockCerebralBridge();
  const submissions: string[] = [];
  const spyBridge = {
    ...bridge,
    submitCommand(input: { rawInput: string; source: string }) {
      submissions.push(input.rawInput);
      return bridge.submitCommand(input);
    }
  };
  const base = loadBootstrapState();
  const store = createBridgeStore(spyBridge, mutate ? mutate(base) : base);
  render(
    <BridgeProvider bridge={spyBridge}>
      <DashboardStateProvider store={store}>
        <ActionStatusProvider>
          <WidgetSlot data={data} labelId="region-widget-right" />
        </ActionStatusProvider>
      </DashboardStateProvider>
    </BridgeProvider>
  );
  return { submissions };
}

function repoButtons(): HTMLButtonElement[] {
  return Array.from(document.querySelectorAll<HTMLButtonElement>("button.widget-list__button"));
}

describe("WidgetSlot repositories (NIC-131)", () => {
  it("renders each repo with its name and current branch", () => {
    renderSlot(reposReady);
    const buttons = repoButtons();
    expect(buttons).toHaveLength(2);
    expect(buttons[0].textContent).toContain("cerebral-helm");
    expect(buttons[0].textContent).toContain("mvp-polish/integrations");
    // A repo with no resolvable branch shows a placeholder, never a fabricated branch.
    expect(buttons[1].textContent).toContain("notes");
    expect(buttons[1].textContent).toContain("—");
  });

  it("opens a repo in the editor via the project grammar on click", () => {
    const { submissions } = renderSlot(reposReady);
    fireEvent.click(repoButtons()[0]);
    expect(submissions).toContain("project /Users/x/Projects/cerebral-helm");
  });

  it("disables the rows under read-only recovery and dispatches nothing", () => {
    const { submissions } = renderSlot(reposReady, (base) => ({ ...base, uiState: "offline" }));
    const buttons = repoButtons();
    expect(buttons[0].disabled).toBe(true);
    fireEvent.click(buttons[0]);
    expect(submissions).toHaveLength(0);
  });

  it("renders an honest empty state without any interactive rows", () => {
    renderSlot({
      widgetId: "repositories",
      state: "empty",
      emptyMessage: "No repositories in your projects folder yet."
    });
    expect(repoButtons()).toHaveLength(0);
    expect(screen.getByText("No repositories in your projects folder yet.")).toBeTruthy();
  });
});

/** NIC-129 Increment 3: the Executive "Projects" widget renders the project folders by name,
 *  in the producer's importance order. Rows are read-only here; click-to-expand is Increment 6. */

const projectsReady: WidgetData = {
  widgetId: "projects",
  state: "ready",
  headline: "2 projects",
  freshness: { observedAt: "2026-07-24T16:00:00.000Z", label: "just now" },
  data: {
    items: [
      {
        id: "CerebralHelm",
        name: "CerebralHelm",
        path: "/Users/x/Projects/CerebralHelm",
        descriptorPath: "/Users/x/Projects/CerebralHelm/PROJECT.md",
        hasDescriptor: true
      },
      { id: "OnDraft", name: "OnDraft", path: "/Users/x/Projects/OnDraft", hasDescriptor: false }
    ]
  }
};

describe("WidgetSlot projects (NIC-129)", () => {
  it("renders each project by name, in the streamed order", () => {
    renderSlot(projectsReady);
    const items = Array.from(document.querySelectorAll(".widget-list__item"));
    expect(items).toHaveLength(2);
    expect(items[0].textContent).toContain("CerebralHelm");
    expect(items[1].textContent).toContain("OnDraft");
  });

  it("is read-only in this increment — no interactive rows yet", () => {
    const { submissions } = renderSlot(projectsReady);
    expect(repoButtons()).toHaveLength(0);
    expect(submissions).toHaveLength(0);
  });

  it("renders an honest empty state", () => {
    renderSlot({
      widgetId: "projects",
      state: "empty",
      emptyMessage: "No projects in your projects folder yet."
    });
    expect(screen.getByText("No projects in your projects folder yet.")).toBeTruthy();
  });
});
