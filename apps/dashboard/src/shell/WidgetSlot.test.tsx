import { render, screen, fireEvent } from "@testing-library/react";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
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

/** NIC-129 Increment 6: the Executive "Projects" widget renders the project folders by name
 *  and opens a project's PROJECT.md in a native detail window on click (shellControl). A
 *  project without a descriptor is non-expandable; read-only recovery disables every row. */

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

interface WebkitTestWindow {
  webkit?: { messageHandlers?: { shellControl?: { postMessage(message: unknown): void } } };
}

describe("WidgetSlot projects (NIC-129)", () => {
  let shellPosts: Array<Record<string, unknown>>;

  beforeEach(() => {
    shellPosts = [];
    (window as unknown as WebkitTestWindow).webkit = {
      messageHandlers: {
        shellControl: { postMessage: (m: unknown) => shellPosts.push(m as Record<string, unknown>) }
      }
    };
  });

  afterEach(() => {
    delete (window as unknown as WebkitTestWindow).webkit;
  });

  it("renders each project by name, in the streamed order", () => {
    renderSlot(projectsReady);
    const buttons = repoButtons();
    expect(buttons).toHaveLength(2);
    expect(buttons[0].textContent).toContain("CerebralHelm");
    expect(buttons[1].textContent).toContain("OnDraft");
  });

  it("opens the detail window for a project with a PROJECT.md on click", () => {
    renderSlot(projectsReady);
    fireEvent.click(repoButtons()[0]);
    expect(shellPosts).toContainEqual({
      action: "openProjectDetail",
      path: "/Users/x/Projects/CerebralHelm"
    });
  });

  it("disables a project with no PROJECT.md and posts nothing on click", () => {
    renderSlot(projectsReady);
    const buttons = repoButtons();
    expect(buttons[1].disabled).toBe(true); // OnDraft: hasDescriptor false → non-expandable
    fireEvent.click(buttons[1]);
    expect(shellPosts).toHaveLength(0);
  });

  it("disables every row under read-only recovery and posts nothing", () => {
    renderSlot(projectsReady, (base) => ({ ...base, uiState: "offline" }));
    const buttons = repoButtons();
    expect(buttons[0].disabled).toBe(true);
    fireEvent.click(buttons[0]);
    expect(shellPosts).toHaveLength(0);
  });

  it("renders an honest empty state without any interactive rows", () => {
    renderSlot({
      widgetId: "projects",
      state: "empty",
      emptyMessage: "No projects in your projects folder yet."
    });
    expect(repoButtons()).toHaveLength(0);
    expect(screen.getByText("No projects in your projects folder yet.")).toBeTruthy();
  });
});

/** NIC-134 Increment 1: the Entertainment "Releases" widget renders new/hot movies and TV
 *  from TMDB with a required source attribution. Rows are non-interactive in this increment
 *  (click-to-search lands in a later increment). */

const releasesReady: WidgetData = {
  widgetId: "releases",
  state: "ready",
  headline: "New & hot",
  freshness: { observedAt: "2026-07-26T16:00:00.000Z", label: "10m ago" },
  data: {
    items: [
      { id: "movie-1", title: "Dune: Part Two", mediaType: "movie", year: 2024 },
      { id: "tv-1", title: "The Bear", mediaType: "tv", year: 2024 },
      { id: "movie-2", title: "Nosferatu", mediaType: "movie" }
    ]
  }
};

describe("WidgetSlot releases (NIC-134)", () => {
  it("renders each release with its title and a Movie/TV · year label", () => {
    renderSlot(releasesReady);
    const items = Array.from(document.querySelectorAll("li.widget-list__item"));
    expect(items).toHaveLength(3);
    expect(items[0].textContent).toContain("Dune: Part Two");
    expect(items[0].textContent).toContain("Movie · 2024");
    expect(items[1].textContent).toContain("The Bear");
    expect(items[1].textContent).toContain("TV · 2024");
  });

  it("drops the year when TMDB has no release date, never fabricating one", () => {
    renderSlot(releasesReady);
    const items = Array.from(document.querySelectorAll("li.widget-list__item"));
    // Nosferatu has no year in the payload: the label is just the kind, no " · ".
    expect(items[2].textContent).toContain("Movie");
    expect(items[2].textContent).not.toContain("·");
  });

  it("shows the required TMDB attribution alongside the data", () => {
    renderSlot(releasesReady);
    expect(screen.getByText(/uses the TMDB API but is not endorsed/i)).toBeTruthy();
  });

  it("renders an honest empty state with no rows or attribution", () => {
    renderSlot({
      widgetId: "releases",
      state: "empty",
      emptyMessage: "No new releases right now."
    });
    expect(document.querySelectorAll("li.widget-list__item")).toHaveLength(0);
    expect(screen.queryByText(/uses the TMDB API/i)).toBeNull();
    expect(screen.getByText("No new releases right now.")).toBeTruthy();
  });
});
