import { render, screen, fireEvent, act } from "@testing-library/react";
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { WidgetSlot, canvasSeason } from "./WidgetSlot";
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

function renderSlot(
  data: WidgetData,
  mutate?: (base: DashboardState) => DashboardState,
  slotWidgetId?: string
) {
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
            <WidgetSlot data={data} labelId="region-widget-right" slotWidgetId={slotWidgetId} />
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

/** NIC-133 Increment 1: the Entertainment "Spotify" widget renders the current track — artwork,
 *  track, artist, optional album, and a playing/paused indicator. Display only in this increment
 *  (playback controls land later); nothing-playing and not-connected are honest slot-level states. */

const spotifyPlaying: WidgetData = {
  widgetId: "spotify",
  state: "ready",
  headline: "Now playing",
  freshness: { observedAt: "2026-07-27T16:00:00.000Z", label: "just now" },
  data: {
    track: "Weightless",
    artist: "Marconi Union",
    album: "Ambient Transmissions Vol. 2",
    artworkImage: "data:image/png;base64,AAAA",
    isPlaying: true
  }
};

function nowPlayingCard(): HTMLElement | null {
  return document.querySelector(".nowplaying");
}

describe("WidgetSlot spotify (NIC-133)", () => {
  it("renders the current track with artwork, track, artist, album, and a playing indicator", () => {
    renderSlot(spotifyPlaying);
    const card = nowPlayingCard();
    expect(card).not.toBeNull();
    expect(card?.querySelector(".nowplaying__track")?.textContent).toBe("Weightless");
    expect(card?.querySelector(".nowplaying__artist")?.textContent).toBe("Marconi Union");
    expect(card?.querySelector(".nowplaying__album")?.textContent).toBe(
      "Ambient Transmissions Vol. 2"
    );
    expect(card?.querySelector("img")?.getAttribute("src")).toBe("data:image/png;base64,AAAA");
    const status = card?.querySelector(".nowplaying__status");
    expect(status?.textContent).toBe("Playing");
    expect(status?.className).toContain("nowplaying__status--playing");
  });

  it("shows a paused indicator when the track is not actively playing", () => {
    renderSlot({
      widgetId: "spotify",
      state: "ready",
      data: { track: "Weightless", artist: "Marconi Union", isPlaying: false }
    });
    const status = nowPlayingCard()?.querySelector(".nowplaying__status");
    expect(status?.textContent).toBe("Paused");
    expect(status?.className).toContain("nowplaying__status--paused");
  });

  it("shows a music-note placeholder when there is no artwork, never a broken image", () => {
    renderSlot({
      widgetId: "spotify",
      state: "ready",
      data: { track: "Untitled", artist: "Unknown", isPlaying: true }
    });
    const card = nowPlayingCard();
    expect(card?.querySelector("img")).toBeNull();
    expect(card?.querySelector(".nowplaying__note")).not.toBeNull();
  });

  it("omits the album line when Spotify provides none, never fabricating one", () => {
    renderSlot({
      widgetId: "spotify",
      state: "ready",
      data: { track: "Untitled", artist: "Unknown", isPlaying: true }
    });
    expect(nowPlayingCard()?.querySelector(".nowplaying__album")).toBeNull();
  });

  it("shows a Recently Played list that opens Spotify when nothing is playing (NIC-133)", () => {
    const { submissions } = renderSlot({
      widgetId: "spotify",
      state: "ready",
      data: {
        recent: [
          { track: "Nightcall", artist: "Kavinsky" },
          { track: "Weightless", artist: "Marconi Union" }
        ]
      }
    });
    // No now-playing card in the idle state.
    expect(document.querySelector(".nowplaying__track")).toBeNull();
    const rows = Array.from(document.querySelectorAll(".nowplaying__recent-row"));
    expect(rows).toHaveLength(2);
    expect(rows[0].textContent).toContain("Nightcall");
    expect(rows[0].textContent).toContain("Kavinsky");
    // Tapping a recent track opens Spotify.
    fireEvent.click(rows[0]);
    expect(submissions).toEqual(["open spotify"]);
  });

  it("renders an honest unavailable state (not connected) with no now-playing card", () => {
    renderSlot({
      widgetId: "spotify",
      state: "unavailable",
      emptyMessage: "Spotify isn't connected yet."
    });
    expect(nowPlayingCard()).toBeNull();
    expect(screen.getByText("Spotify isn't connected yet.")).toBeTruthy();
  });

  it("shows the active device and a progress bar with time labels (NIC-133 polish)", () => {
    renderSlot({
      widgetId: "spotify",
      state: "ready",
      data: {
        track: "Weightless",
        artist: "Marconi Union",
        isPlaying: true,
        deviceName: "Nick's MacBook Pro",
        progressMs: 83000,
        durationMs: 240000
      }
    });
    // The status line names the active device.
    expect(nowPlayingCard()?.querySelector(".nowplaying__status")?.textContent).toBe(
      "Playing · Nick's MacBook Pro"
    );
    // Time labels: current (1:23) and duration (4:00).
    const times = Array.from(document.querySelectorAll(".nowplaying__time")).map((el) => el.textContent);
    expect(times).toEqual(["1:23", "4:00"]);
    // The bar fill reflects ~34.6% (83s / 240s).
    const fill = document.querySelector(".nowplaying__bar-fill") as HTMLElement;
    expect(parseFloat(fill.style.width)).toBeCloseTo(34.58, 1);
  });

  it("shows the Up Next track and an Open-in-Spotify button; no 'just now' stamp (NIC-133 polish)", () => {
    const { submissions } = renderSlot({
      widgetId: "spotify",
      state: "ready",
      data: {
        track: "Weightless",
        artist: "Marconi Union",
        isPlaying: true,
        upNextTrack: "Nightcall",
        upNextArtist: "Kavinsky"
      }
    });
    // Up next line.
    expect(document.querySelector(".nowplaying__upnext-track")?.textContent).toBe("Nightcall — Kavinsky");
    // No freshness label is rendered for this widget.
    expect(document.querySelector(".widget__freshness")).toBeNull();
    // The Open button launches Spotify via the app.open grammar.
    fireEvent.click(screen.getByRole("button", { name: /Open in Spotify/ }));
    expect(submissions).toEqual(["open spotify"]);
  });

  it("omits the Up Next line when the queue is empty/unknown (NIC-133)", () => {
    renderSlot({
      widgetId: "spotify",
      state: "ready",
      data: { track: "Weightless", artist: "Marconi Union", isPlaying: true }
    });
    expect(document.querySelector(".nowplaying__upnext")).toBeNull();
  });

  it("omits the progress bar when duration is unknown, never faking one (NIC-133)", () => {
    renderSlot({
      widgetId: "spotify",
      state: "ready",
      data: { track: "Weightless", artist: "Marconi Union", isPlaying: false }
    });
    expect(document.querySelector(".nowplaying__progress")).toBeNull();
  });

  it("dispatches play/pause/next/previous through the spotify grammar on click (NIC-133)", () => {
    // Playing → the primary control pauses; prev/next skip.
    const { submissions } = renderSlot(spotifyPlaying);
    fireEvent.click(screen.getByRole("button", { name: "Pause" }));
    fireEvent.click(screen.getByRole("button", { name: "Next track" }));
    fireEvent.click(screen.getByRole("button", { name: "Previous track" }));
    expect(submissions).toEqual(["spotify pause", "spotify next", "spotify previous"]);
  });

  it("shows a Play control (not Pause) and dispatches play when the track is paused (NIC-133)", () => {
    const { submissions } = renderSlot({
      widgetId: "spotify",
      state: "ready",
      data: { track: "Weightless", artist: "Marconi Union", isPlaying: false }
    });
    expect(screen.queryByRole("button", { name: "Pause" })).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Play" }));
    expect(submissions).toEqual(["spotify play"]);
  });

  it("optimistically flips play/pause on tap before the server confirms (NIC-133)", () => {
    const { submissions } = renderSlot(spotifyPlaying); // isPlaying: true → shows Pause
    // Tap pause: the icon flips to Play immediately (optimistic), and the command dispatches.
    fireEvent.click(screen.getByRole("button", { name: "Pause" }));
    expect(screen.getByRole("button", { name: "Play" })).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Pause" })).toBeNull();
    expect(submissions).toEqual(["spotify pause"]);
    // The status text flips optimistically too.
    expect(document.querySelector(".nowplaying__status")?.textContent).toBe("Paused");
  });

  it("shows a skip skeleton until the new track lands (NIC-133)", () => {
    renderSlot(spotifyPlaying);
    expect(document.querySelector(".nowplaying__track")?.textContent).toBe("Weightless");
    // Skipping shows a skeleton in place of the track title/artwork.
    fireEvent.click(screen.getByRole("button", { name: "Next track" }));
    expect(document.querySelector(".nowplaying__bone--track")).not.toBeNull();
    expect(document.querySelector(".nowplaying__track")).toBeNull();
    expect(document.querySelector(".nowplaying__art-bone")).not.toBeNull();
  });

  it("disables the controls under read-only recovery and dispatches nothing (NIC-133)", () => {
    const { submissions } = renderSlot(spotifyPlaying, (base) => ({ ...base, uiState: "offline" }));
    const pause = screen.getByRole("button", { name: "Pause" }) as HTMLButtonElement;
    expect(pause.disabled).toBe(true);
    fireEvent.click(pause);
    expect(submissions).toHaveLength(0);
  });
});

/** NIC-132 Increment 1: the School "Courses" widget renders each current course with its name,
 *  code, and a grade ring — the ring fills to the percentage and shows Canvas's own letter grade in
 *  the centre (else the percent, else N/A; a letter is never derived). Fixture-backed in this
 *  increment; click-to-open (the course's Canvas home) lands in a later increment. */

const coursesReady: WidgetData = {
  widgetId: "courses",
  state: "ready",
  headline: "3 courses",
  freshness: { observedAt: "2026-09-14T16:00:00.000Z", label: "4m ago" },
  data: {
    items: [
      // Percent + Canvas letter: the letter wins the ring centre.
      { id: "37331", name: "Theory of Computation", code: "COMPSCI 250", percent: 92.4, letterGrade: "A-" },
      // Percent, no letter: the centre shows the rounded percent.
      { id: "40010", name: "Linear Algebra", code: "MATH 545", percent: 88 },
      // No score yet: an honest N/A with an empty ring — never a fabricated grade.
      { id: "40222", name: "College Writing", code: "ENGLWRIT 112" }
    ]
  }
};

function courseRows(): HTMLLIElement[] {
  return Array.from(document.querySelectorAll<HTMLLIElement>("li.course-row"));
}

function ringLabels(): (string | null | undefined)[] {
  return courseRows().map((r) => r.querySelector(".grade-ring__label")?.textContent);
}

describe("WidgetSlot courses (NIC-132)", () => {
  it("renders each course with its name and code", () => {
    renderSlot(coursesReady);
    const rows = courseRows();
    expect(rows).toHaveLength(3);
    expect(rows[0].querySelector(".course-row__name")?.textContent).toBe("Theory of Computation");
    expect(rows[0].querySelector(".course-row__code")?.textContent).toBe("COMPSCI 250");
  });

  it("shows Canvas's letter grade in the ring centre when it has one, with a filled arc", () => {
    renderSlot(coursesReady);
    const rows = courseRows();
    expect(rows[0].querySelector(".grade-ring__label")?.textContent).toBe("A-");
    // The arc is present and offset to reflect 92.4% (< full circumference).
    const arc = rows[0].querySelector<SVGCircleElement>("circle.grade-ring__arc");
    expect(arc).not.toBeNull();
    expect(parseFloat(arc!.style.strokeDashoffset)).toBeGreaterThan(0);
  });

  it("shows the rounded percentage in the centre when Canvas gives a percent but no letter", () => {
    renderSlot(coursesReady);
    expect(ringLabels()[1]).toBe("88%");
    expect(courseRows()[1].querySelector("circle.grade-ring__arc")).not.toBeNull();
  });

  it("shows an honest N/A with an empty ring when there is no score yet", () => {
    renderSlot(coursesReady);
    const row = courseRows()[2];
    expect(row.querySelector(".grade-ring__label")?.textContent).toBe("N/A");
    // No arc is drawn for a course with no percentage — the ring is empty, not fabricated.
    expect(row.querySelector("circle.grade-ring__arc")).toBeNull();
    expect(row.querySelector(".grade-ring--na")).not.toBeNull();
  });

  it("shows a letter-only grade as a neutral full ring (no percent to fill to)", () => {
    renderSlot({
      widgetId: "courses",
      state: "ready",
      data: { items: [{ id: "1", name: "Seminar", code: "HON 391", letterGrade: "A" }] }
    });
    expect(ringLabels()).toEqual(["A"]);
    const ring = courseRows()[0].querySelector(".grade-ring");
    expect(ring?.className).toContain("grade-ring--neutral");
    expect(ring?.querySelector("circle.grade-ring__arc")).not.toBeNull(); // full, muted
  });

  it("shows a hidden grade honestly and never leaks the hidden score via the ring", () => {
    // The grade is hidden in Canvas but a percent is still present in the payload — the ring must
    // NOT fill to it (that would reveal the score the user hid).
    renderSlot({
      widgetId: "courses",
      state: "ready",
      data: { items: [{ id: "1", name: "Statistics", code: "STAT 240", percent: 80, gradeHidden: true }] }
    });
    const ring = courseRows()[0].querySelector(".grade-ring");
    expect(ring?.querySelector(".grade-ring__label")?.textContent).toBe("—");
    expect(ring?.getAttribute("title")).toBe("Grade hidden in Canvas");
    expect(ring?.querySelector("circle.grade-ring__arc")).toBeNull(); // empty ring, score not leaked
  });

  it("renders the seasonal Canvas empty state with no course rows", () => {
    renderSlot({
      widgetId: "courses",
      state: "empty",
      emptyMessage: "ignored by the seasonal state"
    });
    expect(courseRows()).toHaveLength(0);
    // The School widgets use the date-aware Canvas greeting, not the generic empty message.
    expect(document.querySelector(".canvas-empty")).not.toBeNull();
  });
});

/** NIC-132 Increment 1: the School "Deadlines" widget renders upcoming assignments in due order
 *  (soonest first, submitted/completed excluded by the producer), up to five per page, paging
 *  through the rest with arrows. Fixture-backed; click-to-open lands in a later increment. */

const deadlinesReady: WidgetData = {
  widgetId: "deadlines",
  state: "ready",
  headline: "6 due soon",
  freshness: { observedAt: "2026-09-14T16:00:00.000Z", label: "4m ago" },
  data: {
    items: Array.from({ length: 6 }).map((_, i) => ({
      id: `a${i}`,
      title: `Assignment ${i}`,
      dueAt: `2026-09-1${i}T23:59:00`,
      courseName: "COMPSCI 250"
    }))
  }
};

function deadlineRows(): HTMLLIElement[] {
  return Array.from(document.querySelectorAll<HTMLLIElement>("li.deadline-row"));
}

function deadlineTitles(): (string | null | undefined)[] {
  return deadlineRows().map((r) => r.querySelector(".deadline-row__title")?.textContent);
}

describe("WidgetSlot deadlines (NIC-132)", () => {
  it("shows an assignment's title and its formatted due date", () => {
    renderSlot({
      widgetId: "deadlines",
      state: "ready",
      data: { items: [{ id: "a1", title: "Problem Set 7", dueAt: "2026-09-14T23:59:00" }] }
    });
    const row = deadlineRows()[0];
    expect(row.querySelector(".deadline-row__title")?.textContent).toBe("Problem Set 7");
    expect(row.querySelector(".deadline-row__due")?.textContent).toBe("Sep 14 · 11:59 PM");
  });

  it("omits the due line for an assignment with no due date, never fabricating one", () => {
    renderSlot({
      widgetId: "deadlines",
      state: "ready",
      data: { items: [{ id: "a1", title: "Reading (no due date)" }] }
    });
    expect(deadlineRows()[0].querySelector(".deadline-row__due")).toBeNull();
  });

  it("shows five per page and pages to the rest with the arrow, in the streamed due order", () => {
    renderSlot(deadlinesReady);
    expect(deadlineTitles()).toEqual([
      "Assignment 0",
      "Assignment 1",
      "Assignment 2",
      "Assignment 3",
      "Assignment 4"
    ]);
    fireEvent.click(screen.getByRole("button", { name: "More deadlines" }));
    expect(deadlineTitles()).toEqual(["Assignment 5"]);
    fireEvent.click(screen.getByRole("button", { name: "Previous deadlines" }));
    expect(deadlineTitles()[0]).toBe("Assignment 0");
  });

  it("shows no pager when everything fits on one page", () => {
    renderSlot({
      widgetId: "deadlines",
      state: "ready",
      data: { items: [{ id: "a1", title: "Only one", dueAt: "2026-09-14T09:00:00" }] }
    });
    expect(screen.queryByRole("button", { name: "More deadlines" })).toBeNull();
  });

  it("renders the seasonal Canvas empty state with no deadline rows", () => {
    renderSlot({
      widgetId: "deadlines",
      state: "empty",
      emptyMessage: "ignored by the seasonal state"
    });
    expect(deadlineRows()).toHaveLength(0);
    expect(document.querySelector(".canvas-empty")).not.toBeNull();
  });
});

/** NIC-132 polish: the School widgets' empty/unavailable state is a date-aware Canvas greeting —
 *  a seasonal message over summer/winter break, and a "sync now" nudge (opens Canvas) during term. */

describe("WidgetSlot Canvas seasonal empty (NIC-132)", () => {
  it("shows the seasonal empty over the generic 'Unavailable' bootstrap stub, keyed by the slot id", () => {
    // Before the producer streams, the resolved data is the generic stub (widgetId "left",
    // "Unavailable"); the seasonal state must still show because the slot is a School widget.
    renderSlot({ widgetId: "left", state: "unavailable", emptyMessage: "Unavailable" }, undefined, "deadlines");
    expect(document.querySelector(".canvas-empty")).not.toBeNull();
    expect(screen.queryByText("Unavailable")).toBeNull();
  });

  it("buckets dates into summer / winter / term", () => {
    expect(canvasSeason(new Date(2026, 4, 20))).toBe("summer"); // May 20 (start)
    expect(canvasSeason(new Date(2026, 8, 1))).toBe("summer"); // Sep 1 (end)
    expect(canvasSeason(new Date(2026, 8, 2))).toBe("term"); // Sep 2
    expect(canvasSeason(new Date(2026, 4, 19))).toBe("term"); // May 19
    expect(canvasSeason(new Date(2026, 11, 20))).toBe("winter"); // Dec 20 (start)
    expect(canvasSeason(new Date(2026, 0, 15))).toBe("winter"); // Jan 15
    expect(canvasSeason(new Date(2026, 1, 1))).toBe("winter"); // Feb 1 (end)
    expect(canvasSeason(new Date(2026, 1, 2))).toBe("term"); // Feb 2
    expect(canvasSeason(new Date(2026, 9, 15))).toBe("term"); // Oct 15
  });

  function renderCanvasEmptyAt(
    date: Date,
    state: "empty" | "unavailable",
    widgetId: "deadlines" | "courses" = "deadlines"
  ) {
    vi.useFakeTimers();
    vi.setSystemTime(date);
    try {
      return renderSlot({ widgetId, state, emptyMessage: "ignored by the seasonal state" });
    } finally {
      vi.useRealTimers();
    }
  }

  it("shows a summer greeting over summer break, with no sync button", () => {
    renderCanvasEmptyAt(new Date(2026, 6, 1), "empty"); // July → summer
    expect(screen.getByText("Enjoy your summer!")).toBeTruthy();
    expect(screen.queryByRole("button")).toBeNull();
  });

  it("shows a winter greeting over winter break (also for the unavailable state)", () => {
    renderCanvasEmptyAt(new Date(2026, 0, 5), "unavailable", "courses"); // Jan → winter
    expect(screen.getByText("Enjoy your winter!")).toBeTruthy();
    expect(screen.queryByRole("button")).toBeNull();
  });

  it("nudges to sync during term and opens Canvas on click", () => {
    const { submissions } = renderCanvasEmptyAt(new Date(2026, 9, 15), "empty"); // Oct → term
    expect(screen.getByText("School's back in session – sync courses now!")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Open Canvas to sync" }));
    expect(submissions).toContain("web https://umamherst.instructure.com");
  });

  it("disables the sync nudge under read-only recovery and dispatches nothing", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date(2026, 9, 15)); // term
    try {
      const { submissions } = renderSlot(
        { widgetId: "deadlines", state: "unavailable" },
        (base) => ({ ...base, uiState: "offline" })
      );
      const button = document.querySelector<HTMLButtonElement>(".canvas-empty__logo-button");
      expect(button?.disabled).toBe(true);
      fireEvent.click(button as HTMLButtonElement);
      expect(submissions).toHaveLength(0);
    } finally {
      vi.useRealTimers();
    }
  });
});

/** NIC-132 polish: a course row opens its Canvas home, an assignment row opens the assignment —
 *  both through the web.open path, disabled under read-only recovery. */

describe("WidgetSlot Canvas click-through (NIC-132)", () => {
  it("opens a course in Canvas on click via web.open", () => {
    const { submissions } = renderSlot({
      widgetId: "courses",
      state: "ready",
      headline: "1 course",
      data: {
        items: [
          {
            id: "37331",
            name: "Theory of Computation",
            code: "COMPSCI 250",
            percent: 92,
            url: "https://umamherst.instructure.com/courses/37331"
          }
        ]
      }
    });
    const button = document.querySelector<HTMLButtonElement>("button.course-row__open");
    expect(button).not.toBeNull();
    fireEvent.click(button as HTMLButtonElement);
    expect(submissions).toContain("web https://umamherst.instructure.com/courses/37331");
  });

  it("renders a course without a URL as a non-interactive row", () => {
    renderSlot({ widgetId: "courses", state: "ready", data: { items: [{ id: "1", name: "Seminar" }] } });
    expect(document.querySelector("button.course-row__open")).toBeNull();
    expect(document.querySelector(".course-row__open--static")).not.toBeNull();
  });

  it("disables course rows under read-only recovery and dispatches nothing", () => {
    const { submissions } = renderSlot(
      {
        widgetId: "courses",
        state: "ready",
        data: { items: [{ id: "1", name: "X", url: "https://umamherst.instructure.com/courses/1" }] }
      },
      (base) => ({ ...base, uiState: "offline" })
    );
    const button = document.querySelector<HTMLButtonElement>("button.course-row__open");
    expect(button?.disabled).toBe(true);
    fireEvent.click(button as HTMLButtonElement);
    expect(submissions).toHaveLength(0);
  });

  it("opens an assignment in Canvas on click", () => {
    const { submissions } = renderSlot({
      widgetId: "deadlines",
      state: "ready",
      data: {
        items: [
          {
            id: "a1",
            title: "Problem Set 7",
            dueAt: "2026-09-14T23:59:00",
            url: "https://umamherst.instructure.com/courses/37331/assignments/1"
          }
        ]
      }
    });
    fireEvent.click(document.querySelector("button.deadline-row__open") as HTMLButtonElement);
    expect(submissions).toContain("web https://umamherst.instructure.com/courses/37331/assignments/1");
  });
});
