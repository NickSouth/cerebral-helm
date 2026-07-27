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

/** NIC-128 Increment 1: the Executive "Stocks" widget renders a configured list of tickers as
 *  compact tiles with price + day movement (up/down coloured), 4 to a 2×2 page, paging through
 *  more. Fixture-backed in this increment (the live Finnhub producer lands later). */

const stocksReady: WidgetData = {
  widgetId: "stocks",
  state: "ready",
  headline: "Markets up modestly",
  freshness: { observedAt: "2026-07-26T16:00:00.000Z", label: "2m ago" },
  data: {
    items: [
      { symbol: "SPY", price: 543.21, change: 3.24, changePercent: 0.6, history: [530, 535, 532, 540, 543.21] },
      { symbol: "AAPL", price: 227.15, change: -0.68, changePercent: -0.3, history: [231, 229, 228, 227.15] },
      // A symbol the provider couldn't resolve: figures omitted, never fabricated.
      { symbol: "???" }
    ]
  }
};

/** Six tickers so the widget pages 4-at-a-time (page 1 = 4 tiles, page 2 = 2 tiles). */
const stocksTwoPages: WidgetData = {
  widgetId: "stocks",
  state: "ready",
  headline: "Markets",
  data: {
    items: Array.from({ length: 6 }).map((_, i) => ({
      symbol: `T${i}`,
      price: 100 + i,
      change: 1,
      changePercent: 1
    }))
  }
};

function stockCards(): HTMLLIElement[] {
  return Array.from(document.querySelectorAll<HTMLLIElement>("li.stock-card"));
}

function stockSymbols(): (string | null | undefined)[] {
  return stockCards().map((c) => c.querySelector(".stock-card__symbol")?.textContent);
}

describe("WidgetSlot stocks (NIC-128)", () => {
  it("renders each ticker with its symbol, price, and signed change/percent", () => {
    renderSlot(stocksReady);
    const cards = stockCards();
    expect(cards).toHaveLength(3);
    expect(cards[0].textContent).toContain("SPY");
    expect(cards[0].textContent).toContain("543.21");
    expect(cards[0].textContent).toContain("+3.24 (+0.60%)");
    expect(cards[1].textContent).toContain("-0.68 (-0.30%)");
  });

  it("colours a gainer up and a loser down via the tile modifier class", () => {
    renderSlot(stocksReady);
    const cards = stockCards();
    expect(cards[0].className).toContain("stock-card--up"); // SPY +3.24
    expect(cards[1].className).toContain("stock-card--down"); // AAPL -0.68
  });

  it("shows a muted em-dash for an unresolved symbol, never a fabricated 0", () => {
    renderSlot(stocksReady);
    const card = stockCards()[2]; // "???" — no price/change
    expect(card.querySelector(".stock-card__price")?.textContent).toBe("—");
    expect(card.querySelector(".stock-card__change")?.textContent).toBe("—");
    expect(card.className).toContain("stock-card--flat");
  });

  it("draws a month-trend sparkline coloured by direction, and omits it when there is no history", () => {
    renderSlot(stocksReady);
    const cards = stockCards();
    // SPY gained → an up-coloured sparkline whose polyline has one point per close.
    const spy = cards[0].querySelector("svg.stock-card__spark");
    expect(spy?.getAttribute("class")).toContain("stock-card__spark--up");
    expect(spy?.querySelector("polyline")?.getAttribute("points")?.split(" ")).toHaveLength(5);
    // AAPL fell → a down-coloured sparkline.
    expect(cards[1].querySelector("svg.stock-card__spark")?.getAttribute("class")).toContain(
      "stock-card__spark--down"
    );
    // The unresolved "???" tile has no history → no sparkline.
    expect(cards[2].querySelector("svg.stock-card__spark")).toBeNull();
  });

  it("shows four tickers per page and pages to the rest with the arrow", () => {
    renderSlot(stocksTwoPages);
    expect(stockSymbols()).toEqual(["T0", "T1", "T2", "T3"]);
    fireEvent.click(screen.getByRole("button", { name: "More tickers" }));
    expect(stockSymbols()).toEqual(["T4", "T5"]);
  });

  it("auto-advances to the next page on the autoplay interval, wrapping (NIC-128)", () => {
    vi.useFakeTimers();
    try {
      renderSlot(stocksTwoPages); // 6 items → 2 pages
      expect(stockSymbols()).toEqual(["T0", "T1", "T2", "T3"]);
      act(() => {
        vi.advanceTimersByTime(30_000);
      });
      expect(stockSymbols()).toEqual(["T4", "T5"]);
    } finally {
      vi.useRealTimers();
    }
  });

  it("renders an honest empty state with no tiles", () => {
    renderSlot({
      widgetId: "stocks",
      state: "empty",
      emptyMessage: "Add tickers in Settings → Setup to track them here."
    });
    expect(stockCards()).toHaveLength(0);
    expect(screen.getByText("Add tickers in Settings → Setup to track them here.")).toBeTruthy();
  });
});

/** NIC-130 Increment 1: the Developer "Project Git Status" widget renders a per-repo report one
 *  repo at a time (arrows swap between repos): local branch + remote-sync (always shown) plus the
 *  read-only GitHub sections (open PRs, CI, recent commits). A repo with no CI omits the CI line;
 *  a non-GitHub remote or unreachable GitHub degrades to an honest note. Fixture-backed here (the
 *  live GitHub producer lands in a later increment). */

const gitStatusReady: WidgetData = {
  widgetId: "project-git-status",
  state: "ready",
  headline: "3 repositories",
  freshness: { observedAt: "2026-07-27T16:00:00.000Z", label: "just now" },
  data: {
    repositories: [
      {
        id: "cerebral-helm",
        name: "cerebral-helm",
        branch: "mvp-polish/integrations",
        sync: "diverged",
        remote: { owner: "NickSouth", repo: "cerebral-helm" },
        github: {
          state: "ready",
          openPullRequests: { count: 2, titles: ["Repo status widget", "Weather integration"] },
          checks: { state: "passing" },
          recentCommits: [
            { shortSha: "320ac4c", message: "fix: news formatting" },
            { shortSha: "c1a4f7e", message: "feat: news widget" }
          ]
        }
      },
      {
        id: "notes",
        name: "notes",
        branch: "main",
        sync: "synced",
        remote: { owner: "NickSouth", repo: "notes" },
        github: {
          state: "ready",
          openPullRequests: { count: 0, titles: [] },
          checks: { state: "none" },
          recentCommits: [{ shortSha: "a1b2c3d", message: "Add reading list" }]
        }
      },
      { id: "scratchpad", name: "scratchpad", branch: "wip", sync: "no-upstream" }
    ]
  }
};

function gitRepoName(): string | null | undefined {
  return document.querySelector(".gitstatus__repo .repo-row__label")?.textContent;
}

function nextRepo(): void {
  fireEvent.click(screen.getByRole("button", { name: "Next repository" }));
}

describe("WidgetSlot project-git-status (NIC-130)", () => {
  it("renders the active repo with its branch, sync state, open PRs, CI, and recent commits", () => {
    renderSlot(gitStatusReady);
    expect(gitRepoName()).toBe("cerebral-helm");
    expect(document.querySelector(".gitstatus__repo .repo-row__branch")?.textContent).toBe(
      "mvp-polish/integrations"
    );
    expect(document.querySelector(".gitstatus__sync")?.textContent).toBe("Diverged from origin");
    // Open PRs: the count and each title.
    expect(document.querySelector(".gitstatus__value")?.textContent).toBe("2");
    const prTitles = Array.from(document.querySelectorAll(".gitstatus__pr")).map(
      (el) => el.textContent
    );
    expect(prTitles).toEqual(["Repo status widget", "Weather integration"]);
    // CI is shown as passing.
    expect(document.querySelector(".gitstatus__checks")?.textContent).toBe("Passing");
    // Recent commits: message + short SHA.
    const commits = Array.from(document.querySelectorAll(".gitstatus__msg")).map(
      (el) => el.textContent
    );
    expect(commits).toEqual(["fix: news formatting", "feat: news widget"]);
    expect(document.querySelector(".gitstatus__sha")?.textContent).toBe("320ac4c");
  });

  it("omits the CI line entirely for a repo with no CI, but still shows the rest", () => {
    renderSlot(gitStatusReady);
    nextRepo(); // → notes: checks state "none"
    expect(gitRepoName()).toBe("notes");
    expect(document.querySelector(".gitstatus__checks")).toBeNull(); // no CI row at all
    expect(document.querySelector(".gitstatus__sync")?.textContent).toBe("In sync with origin");
    expect(document.querySelector(".gitstatus__value")?.textContent).toBe("0"); // 0 open PRs
  });

  it("shows a quiet note for a non-GitHub repo while still showing local branch and sync", () => {
    renderSlot(gitStatusReady);
    nextRepo();
    nextRepo(); // → scratchpad: no remote
    expect(gitRepoName()).toBe("scratchpad");
    expect(document.querySelector(".gitstatus__note")?.textContent).toBe("Not a GitHub repository");
    expect(document.querySelector(".gitstatus__repo .repo-row__branch")?.textContent).toBe("wip");
    expect(document.querySelector(".gitstatus__sync")?.textContent).toBe("No upstream branch");
    // No GitHub sections for a local-only repo.
    expect(document.querySelector(".gitstatus__value")).toBeNull();
    expect(document.querySelector(".gitstatus__checks")).toBeNull();
  });

  it("degrades to an honest note when GitHub is unavailable, keeping local branch and sync", () => {
    renderSlot({
      widgetId: "project-git-status",
      state: "ready",
      headline: "1 repository",
      data: {
        repositories: [
          {
            id: "cerebral-helm",
            name: "cerebral-helm",
            branch: "main",
            sync: "synced",
            remote: { owner: "NickSouth", repo: "cerebral-helm" },
            github: { state: "unavailable", message: "Add your GitHub token in Settings → Setup." }
          }
        ]
      }
    });
    expect(document.querySelector(".gitstatus__note")?.textContent).toBe(
      "Add your GitHub token in Settings → Setup."
    );
    expect(document.querySelector(".gitstatus__sync")?.textContent).toBe("In sync with origin");
    expect(document.querySelector(".gitstatus__value")).toBeNull();
  });

  it("degrades to an honest note when GitHub is rate-limited", () => {
    renderSlot({
      widgetId: "project-git-status",
      state: "ready",
      headline: "1 repository",
      data: {
        repositories: [
          {
            id: "cerebral-helm",
            name: "cerebral-helm",
            branch: "main",
            sync: "synced",
            remote: { owner: "NickSouth", repo: "cerebral-helm" },
            github: { state: "rate-limited", message: "GitHub is rate-limited until 16:30." }
          }
        ]
      }
    });
    expect(document.querySelector(".gitstatus__note")?.textContent).toBe(
      "GitHub is rate-limited until 16:30."
    );
  });

  it("pages between repositories with the arrows, one repo at a time", () => {
    renderSlot(gitStatusReady);
    expect(gitRepoName()).toBe("cerebral-helm");
    nextRepo();
    expect(gitRepoName()).toBe("notes");
    fireEvent.click(screen.getByRole("button", { name: "Previous repository" }));
    expect(gitRepoName()).toBe("cerebral-helm");
  });

  it("renders an honest empty state with no report", () => {
    renderSlot({
      widgetId: "project-git-status",
      state: "empty",
      emptyMessage: "No repositories in your projects folder yet."
    });
    expect(document.querySelector(".gitstatus")).toBeNull();
    expect(screen.getByText("No repositories in your projects folder yet.")).toBeTruthy();
  });
});
