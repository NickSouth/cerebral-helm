import { render, screen, fireEvent, act } from "@testing-library/react";
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { WidgetSlot } from "./WidgetSlot";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { BridgeProvider } from "../state/BridgeProvider";
import { ActionStatusProvider } from "../state/ActionStatusProvider";
import { AppearanceProvider } from "../state/AppearanceProvider";
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
        <AppearanceProvider>
          <ActionStatusProvider>
            <WidgetSlot data={data} labelId="region-widget-right" />
          </ActionStatusProvider>
        </AppearanceProvider>
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
      {
        id: "movie-1",
        title: "Dune: Part Two",
        mediaType: "movie",
        year: 2024,
        posterImage: "data:image/jpeg;base64,AAAA"
      },
      { id: "tv-1", title: "The Bear", mediaType: "tv", year: 2024 },
      { id: "movie-2", title: "Nosferatu", mediaType: "movie" }
    ]
  }
};

/** Eight releases (4 movies + 4 shows) so the widget pages 4-at-a-time. */
const releasesTwoPages: WidgetData = {
  widgetId: "releases",
  state: "ready",
  headline: "New & hot",
  data: {
    items: Array.from({ length: 8 }).map((_, i) => ({
      id: `r${i}`,
      title: `Title ${i}`,
      mediaType: i % 2 === 0 ? "movie" : "tv",
      year: 2024
    }))
  }
};

function releaseCards(): HTMLButtonElement[] {
  return Array.from(document.querySelectorAll<HTMLButtonElement>("button.release-card"));
}

function cardTitles(): (string | null | undefined)[] {
  return releaseCards().map((c) => c.querySelector(".release-card__title")?.textContent);
}

describe("WidgetSlot releases (NIC-134)", () => {
  it("shows two releases per page as cards with title and Movie/TV · year meta", () => {
    renderSlot(releasesReady);
    const cards = releaseCards();
    expect(cards).toHaveLength(2); // 1 movie + 1 show per page
    expect(cards[0].textContent).toContain("Dune: Part Two");
    expect(cards[0].textContent).toContain("Movie · 2024");
    expect(cards[1].textContent).toContain("The Bear");
    expect(cards[1].textContent).toContain("TV · 2024");
  });

  it("shows the poster image when present and a kind placeholder when absent", () => {
    renderSlot(releasesReady);
    const cards = releaseCards();
    // Dune has a poster; The Bear does not → a placeholder, no image.
    expect(cards[0].querySelector("img")?.getAttribute("src")).toBe("data:image/jpeg;base64,AAAA");
    expect(cards[1].querySelector("img")).toBeNull();
    expect(cards[1].querySelector(".release-card__placeholder")?.textContent).toBe("TV");
  });

  it("drops the year when TMDB has no release date, never fabricating one", () => {
    renderSlot(releasesReady);
    // Nosferatu (no year) is on page 2.
    fireEvent.click(screen.getByRole("button", { name: "More releases" }));
    const card = releaseCards()[0];
    expect(card.textContent).toContain("Nosferatu");
    expect(card.textContent).toContain("Movie");
    expect(card.textContent).not.toContain("·");
  });

  it("renders an honest empty state with no cards", () => {
    renderSlot({
      widgetId: "releases",
      state: "empty",
      emptyMessage: "No new releases right now."
    });
    expect(releaseCards()).toHaveLength(0);
    expect(screen.getByText("No new releases right now.")).toBeTruthy();
  });

  it("clicking a release submits a 'where to watch' Google search (NIC-134)", () => {
    const { submissions } = renderSlot(releasesReady);
    fireEvent.click(releaseCards()[0]);
    expect(submissions).toEqual(["google where to watch Dune: Part Two"]);
  });

  it("pages 2 releases at a time; the arrow reveals the next pair (NIC-134)", () => {
    renderSlot(releasesTwoPages);
    expect(cardTitles()).toEqual(["Title 0", "Title 1"]);
    fireEvent.click(screen.getByRole("button", { name: "More releases" }));
    expect(cardTitles()).toEqual(["Title 2", "Title 3"]);
  });

  it("auto-advances to the next page on the autoplay interval, wrapping (NIC-134)", () => {
    vi.useFakeTimers();
    try {
      renderSlot(releasesTwoPages); // 8 items → 4 pages
      expect(cardTitles()).toEqual(["Title 0", "Title 1"]);
      act(() => {
        vi.advanceTimersByTime(30_000);
      });
      expect(cardTitles()).toEqual(["Title 2", "Title 3"]);
    } finally {
      vi.useRealTimers();
    }
  });
});
