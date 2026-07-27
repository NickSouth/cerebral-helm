import { useEffect, useState, type ReactNode } from "react";
import { Panel } from "./Panel";
import { PanelGlyph, type PanelGlyphName } from "./PanelGlyph";
import { StaleMarker } from "../components/StaleMarker";
import { SkeletonBone } from "../components/Skeleton";
import { Unavailable } from "../components/Unavailable";
import { EmptyState } from "../components/EmptyState";
import { WIDGET_REGISTRY } from "../widgets/widgets";
import type {
  GitHubChecksState,
  GitSyncState,
  ProjectGitStatusItem,
  ProjectWidgetItem,
  ReleaseWidgetItem,
  RepositoryWidgetItem,
  SpotifyRecentTrack,
  SpotifyWidgetPayload,
  StockQuoteWidgetItem,
  WidgetData
} from "../widgets/widgetData";
import { useBridge } from "../state/BridgeProvider";
import { useActionStatus } from "../state/ActionStatusProvider";
import { useAppearance } from "../state/AppearanceProvider";
import { useUiPosture } from "../state/useUiPosture";
import { submitOpenProject } from "./openProject";
import { submitOpenProjectDetail } from "./openProjectDetail";
import { submitGoogleSearch } from "./googleSearch";
import { submitSpotifyControl, type SpotifyControlAction } from "./spotifyControl";
import { submitOpenApp } from "./openApp";
import { formatDay } from "./format";

const WIDGET_LABELS: ReadonlyMap<string, string> = new Map(
  WIDGET_REGISTRY.map((widget) => [widget.id, widget.label])
);

/** Icon-first annotation per widget id (visual reference); unknown ids fall back to a generic glyph. */
const WIDGET_ICONS: Readonly<Record<string, PanelGlyphName>> = {
  stocks: "market",
  "project-git-status": "git",
  repositories: "git",
  projects: "projects",
  deadlines: "deadlines",
  spotify: "music",
  courses: "courses",
  releases: "media"
};

/** Human label for a release's media type (never a fabricated category). */
function releaseKindLabel(mediaType: unknown): string {
  return mediaType === "tv" ? "TV" : "Movie";
}

/** "Movie · 2025" / "TV · 2024" / "Movie" — year is dropped when TMDB has no release date. */
function releaseMeta(item: { mediaType?: unknown; year?: unknown }): string {
  const kind = releaseKindLabel(item.mediaType);
  return typeof item.year === "number" ? `${kind} · ${item.year}` : kind;
}

function row(primary: ReactNode, secondary: ReactNode, key: string | number) {
  return (
    <li key={key} className="widget-list__item">
      <span className="widget-list__primary">{primary}</span>
      <span className="widget-list__secondary">{secondary}</span>
    </li>
  );
}

function list(children: ReactNode) {
  return <ul className="widget-list">{children}</ul>;
}

/**
 * Per-widget body renderers, keyed by widget id — the registry-driven slot (design spec
 * §5.3): a widget id resolves to its own renderer, never a per-mode conditional. Each reads
 * its slice of the WidgetData payload.
 *
 * The payload is intentionally heterogeneous: each renderer knows only its own widget's
 * shape, so `data` is untyped at this dispatch boundary (WidgetBody hands it in as an
 * unknown-derived record). Typed per-widget payloads are deferred to the widget-data
 * contract work; the explicit-any allowance is scoped to this registry only.
 */
/* eslint-disable @typescript-eslint/no-explicit-any */
const WIDGET_BODIES: Readonly<Record<string, (data: any) => ReactNode>> = {
  deadlines: (data) =>
    list(
      (data.items ?? []).map((item: any, index: number) =>
        row(item.title, formatDay(item.dueAt), index)
      )
    ),
  courses: (data) =>
    list((data.items ?? []).map((item: any, index: number) => row(item.name, item.next, index)))
};
/* eslint-enable @typescript-eslint/no-explicit-any */

/** A small line-icon folder mark for a repo row (matches the PanelGlyph line-icon convention). */
function FolderGlyph() {
  return (
    <svg
      className="repo-row__icon"
      viewBox="0 0 24 24"
      width="15"
      height="15"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M4 7.5A1.5 1.5 0 0 1 5.5 6h3l2 2h8A1.5 1.5 0 0 1 20 9.5v7a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 16.5z" />
    </svg>
  );
}

/**
 * The Developer "Repositories" widget body (NIC-131): each active repo is a clickable row
 * showing its name and current branch. Clicking opens the repo in the configured editor
 * through the gated `project.open` path (`submitOpenProject`); read-only recovery disables
 * the rows, and a rejected dispatch is surfaced honestly in the status line — never a
 * fabricated success. Unlike the static renderers, this needs the bridge/posture/status
 * hooks, so it is a component rather than a pure `(data) => ReactNode` entry.
 */
function RepositoriesBody({ items }: { items: readonly RepositoryWidgetItem[] }) {
  const bridge = useBridge();
  const { announce } = useActionStatus();
  const { readOnly } = useUiPosture();

  const open = (item: RepositoryWidgetItem) => {
    void submitOpenProject(bridge, item.path)
      .then((receipt) => {
        if (!receipt.accepted) {
          announce(`I couldn't open ${item.name} — the command wasn't accepted.`, "error");
        }
      })
      .catch(() => {
        announce(`Opening ${item.name} failed — the bridge did not accept it.`, "error");
      });
  };

  return (
    <ul className="widget-list">
      {items.map((item) => (
        <li key={item.id} className="widget-list__item">
          <button
            type="button"
            className="widget-list__button"
            disabled={readOnly}
            aria-disabled={readOnly || undefined}
            title={
              readOnly
                ? "Opening a repository is paused while the dashboard is read-only"
                : `Open ${item.name} in the editor`
            }
            onClick={() => {
              open(item);
            }}
          >
            <span className="repo-row__name">
              <FolderGlyph />
              <span className="repo-row__label">{item.name}</span>
            </span>
            {item.branch ? (
              <code className="repo-row__branch">{item.branch}</code>
            ) : (
              <span className="repo-row__branch repo-row__branch--none" aria-label="no branch">
                —
              </span>
            )}
          </button>
        </li>
      ))}
    </ul>
  );
}

/**
 * The Executive "Projects" widget body (NIC-129): each project is a clickable row that opens
 * its `PROJECT.md` in a native detail window (`shellControl.openProjectDetail`, owned by the
 * `WindowCoordinator`). A project with no descriptor is honestly non-expandable — the row is
 * disabled rather than opening an empty window — and read-only recovery disables every row.
 * Like `RepositoriesBody`, this needs the posture hook, so it is a component rather than a
 * static `WIDGET_BODIES` entry.
 */
function ProjectsBody({ items }: { items: readonly ProjectWidgetItem[] }) {
  const { readOnly } = useUiPosture();

  return (
    <ul className="widget-list">
      {items.map((item) => {
        const expandable = item.hasDescriptor && !readOnly;
        return (
          <li key={item.id} className="widget-list__item">
            <button
              type="button"
              className="widget-list__button"
              disabled={!expandable}
              aria-disabled={!expandable || undefined}
              title={
                readOnly
                  ? "Opening a project is paused while the dashboard is read-only"
                  : item.hasDescriptor
                    ? `Open ${item.name}`
                    : `${item.name} has no PROJECT.md yet`
              }
              onClick={() => {
                submitOpenProjectDetail(item.path);
              }}
            >
              <span className="repo-row__name">
                <FolderGlyph />
                <span className="repo-row__label">{item.name}</span>
              </span>
            </button>
          </li>
        );
      })}
    </ul>
  );
}

/**
 * The Entertainment "Releases" widget body (NIC-134): each release is a clickable row that opens
 * a "where to watch <title>" Google search in the browser through the gated `google.search` path
 * (`submitGoogleSearch`). Read-only recovery disables the rows, and a rejected dispatch is
 * surfaced honestly in the status line — never a fabricated success. TMDB attribution is required
 * by their API terms and always shown. Like `RepositoriesBody`, this needs the bridge/posture/
 * status hooks, so it is a component rather than a static `WIDGET_BODIES` entry.
 */
/** Releases are shown 2 at a time (1 movie + 1 show, full poster size); arrows page through more,
 *  and the carousel auto-advances on this interval (paused under reduced motion). */
const RELEASES_PER_PAGE = 2;
const RELEASES_AUTOPLAY_MS = 30_000;

function ReleasesBody({ items }: { items: readonly ReleaseWidgetItem[] }) {
  const bridge = useBridge();
  const { announce } = useActionStatus();
  const { readOnly } = useUiPosture();
  const { reducedMotion } = useAppearance();
  const [page, setPage] = useState(0);

  const pageCount = Math.max(1, Math.ceil(items.length / RELEASES_PER_PAGE));
  const safePage = Math.min(page, pageCount - 1);
  const start = safePage * RELEASES_PER_PAGE;
  const pageItems = items.slice(start, start + RELEASES_PER_PAGE);

  // Auto-advance to the next page every 30s, wrapping. Keyed on `safePage`, so a manual arrow
  // press resets the countdown (a fresh 30s before the next auto-advance). Disabled when there is
  // only one page or the user prefers reduced motion.
  useEffect(() => {
    if (pageCount <= 1 || reducedMotion) return;
    const id = window.setInterval(() => {
      setPage((current) => (current + 1) % pageCount);
    }, RELEASES_AUTOPLAY_MS);
    return () => window.clearInterval(id);
  }, [pageCount, reducedMotion, safePage]);

  const openWhereToWatch = (item: ReleaseWidgetItem) => {
    void submitGoogleSearch(bridge, `where to watch ${item.title}`)
      .then((receipt) => {
        if (!receipt.accepted) {
          announce(`I couldn't search for ${item.title} — the command wasn't accepted.`, "error");
        }
      })
      .catch(() => {
        announce(`Searching for ${item.title} failed — the bridge did not accept it.`, "error");
      });
  };

  return (
    <div className="releases">
      {pageCount > 1 ? (
        <div className="releases__pager">
          <button
            type="button"
            className="releases__arrow"
            disabled={safePage === 0}
            aria-label="Previous releases"
            onClick={() => setPage(safePage - 1)}
          >
            ‹
          </button>
          <span className="releases__dots">
            {Array.from({ length: pageCount }).map((_, index) => (
              <span
                key={index}
                className={`releases__dot${index === safePage ? " releases__dot--active" : ""}`}
                aria-hidden="true"
              />
            ))}
          </span>
          <button
            type="button"
            className="releases__arrow"
            disabled={safePage >= pageCount - 1}
            aria-label="More releases"
            onClick={() => setPage(safePage + 1)}
          >
            ›
          </button>
        </div>
      ) : null}
      <ul className="releases__grid">
        {pageItems.map((item, index) => (
          <li key={item.id ?? index} className="releases__cell">
            <button
              type="button"
              className="release-card"
              disabled={readOnly}
              aria-disabled={readOnly || undefined}
              title={
                readOnly
                  ? "Searching is paused while the dashboard is read-only"
                  : `Find where to watch ${item.title}`
              }
              onClick={() => {
                openWhereToWatch(item);
              }}
            >
              <span className="release-card__poster">
                {item.posterImage ? (
                  <img src={item.posterImage} alt="" loading="lazy" />
                ) : (
                  <span className="release-card__placeholder">{releaseKindLabel(item.mediaType)}</span>
                )}
              </span>
              <span className="release-card__title">{item.title}</span>
              <span className="release-card__meta">{releaseMeta(item)}</span>
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}

/**
 * The Executive "Stocks" widget body (NIC-128): a configured list of tickers, each shown as a
 * compact tile with its price and day movement (absolute + percent), up/down coloured. Tiles
 * fill a 2×2 grid (4 per page); adding more paginates through pages with arrows + dots and a
 * 30s auto-advance (paused under reduced motion, mirroring the releases carousel). Missing
 * figures render as a muted "—" — an unresolved symbol is honest, never a fabricated $0. This
 * widget is read-only (no click-through), but it owns pager state and the reduced-motion hook,
 * so it is a component rather than a static `WIDGET_BODIES` entry.
 */
const STOCKS_PER_PAGE = 4;
const STOCKS_AUTOPLAY_MS = 30_000;

/** "543.21" with two decimals; a muted em-dash when the price couldn't be resolved. */
function formatStockPrice(price: number | undefined): string {
  return typeof price === "number"
    ? price.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
    : "—";
}

/** The colour/direction cue for a day change (paired with the signed text so colour is never the
 *  only signal): positive → up, negative → down, zero/unknown → flat. */
function stockDirection(change: number | undefined): "up" | "down" | "flat" {
  if (typeof change !== "number" || change === 0) return "flat";
  return change > 0 ? "up" : "down";
}

/** "+3.24 (+0.60%)" / "-0.68 (-0.30%)"; a muted em-dash when either figure is unknown. */
function formatStockChange(item: StockQuoteWidgetItem): string {
  if (typeof item.change !== "number" || typeof item.changePercent !== "number") return "—";
  const sign = item.change > 0 ? "+" : ""; // a negative value already carries its own "-"
  return `${sign}${item.change.toFixed(2)} (${sign}${item.changePercent.toFixed(2)}%)`;
}

/**
 * A tiny month-trend sparkline for a stock tile (NIC-128): a single `<polyline>`, no axes or
 * dots, coloured by the day's direction (green up / red down / muted flat — matching the change
 * chip). The closes are mapped to a fixed 0–100 × 0–100 viewBox and the SVG stretches to fill the
 * tile with `preserveAspectRatio="none"`; the stroke stays crisp via `vector-effect`. Renders
 * nothing when there are fewer than two points (never a degenerate line).
 */
function StockSparkline({
  history,
  direction
}: {
  history: readonly number[];
  direction: "up" | "down" | "flat";
}) {
  if (history.length < 2) return null;
  const min = Math.min(...history);
  const max = Math.max(...history);
  const span = max - min || 1; // a flat series maps to a centered horizontal line, not NaN
  const stepX = 100 / (history.length - 1);
  const points = history
    .map((value, index) => {
      const x = index * stepX;
      const y = 100 - ((value - min) / span) * 100; // SVG y grows downward
      return `${x.toFixed(2)},${y.toFixed(2)}`;
    })
    .join(" ");

  return (
    <svg
      className={`stock-card__spark stock-card__spark--${direction}`}
      viewBox="0 0 100 100"
      preserveAspectRatio="none"
      aria-hidden="true"
      focusable="false"
    >
      <polyline points={points} fill="none" vectorEffect="non-scaling-stroke" strokeWidth="1.5" />
    </svg>
  );
}

function StocksBody({ items }: { items: readonly StockQuoteWidgetItem[] }) {
  const { reducedMotion } = useAppearance();
  const [page, setPage] = useState(0);

  const pageCount = Math.max(1, Math.ceil(items.length / STOCKS_PER_PAGE));
  const safePage = Math.min(page, pageCount - 1);
  const start = safePage * STOCKS_PER_PAGE;
  const pageItems = items.slice(start, start + STOCKS_PER_PAGE);

  // Auto-advance to the next page every 30s, wrapping. Keyed on `safePage`, so a manual arrow
  // press resets the countdown. Disabled when there is only one page or the user prefers reduced
  // motion (matching the releases carousel).
  useEffect(() => {
    if (pageCount <= 1 || reducedMotion) return;
    const id = window.setInterval(() => {
      setPage((current) => (current + 1) % pageCount);
    }, STOCKS_AUTOPLAY_MS);
    return () => window.clearInterval(id);
  }, [pageCount, reducedMotion, safePage]);

  return (
    <div className="stocks">
      {pageCount > 1 ? (
        <div className="stocks__pager">
          <button
            type="button"
            className="stocks__arrow"
            disabled={safePage === 0}
            aria-label="Previous tickers"
            onClick={() => setPage(safePage - 1)}
          >
            ‹
          </button>
          <span className="stocks__dots">
            {Array.from({ length: pageCount }).map((_, index) => (
              <span
                key={index}
                className={`stocks__dot${index === safePage ? " stocks__dot--active" : ""}`}
                aria-hidden="true"
              />
            ))}
          </span>
          <button
            type="button"
            className="stocks__arrow"
            disabled={safePage >= pageCount - 1}
            aria-label="More tickers"
            onClick={() => setPage(safePage + 1)}
          >
            ›
          </button>
        </div>
      ) : null}
      <ul className="stocks__grid">
        {pageItems.map((item, index) => {
          const direction = stockDirection(item.change);
          return (
            <li key={item.symbol ?? index} className={`stock-card stock-card--${direction}`}>
              <span className="stock-card__symbol">{item.symbol}</span>
              <span className="stock-card__price">{formatStockPrice(item.price)}</span>
              <span className="stock-card__change">{formatStockChange(item)}</span>
              {item.history && item.history.length >= 2 ? (
                <StockSparkline history={item.history} direction={direction} />
              ) : null}
            </li>
          );
        })}
      </ul>
    </div>
  );
}

/** Human label for the local branch's relationship to its `origin` remote-tracking ref. */
const GIT_SYNC_LABELS: Readonly<Record<GitSyncState, string>> = {
  synced: "In sync with origin",
  diverged: "Diverged from origin",
  "no-upstream": "No upstream branch"
};

/** Human label for a CI state (`none` never reaches here — that line is omitted, not labelled). */
const GITHUB_CHECKS_LABELS: Readonly<Record<Exclude<GitHubChecksState, "none">, string>> = {
  passing: "Passing",
  failing: "Failing",
  pending: "Pending"
};

/**
 * The GitHub half of a repo's report (NIC-130): open PRs, CI state, and recent commits, read-only.
 * Present only for a GitHub remote — a non-GitHub `origin` shows a quiet note while the local
 * branch/sync above still stands. GitHub being unreachable or rate-limited degrades to an honest
 * line rather than a fabricated success. A repo with no CI (`checks.state === "none"`) omits the CI
 * line entirely, so a repo without CI reads as complete rather than broken.
 */
function GitHubReport({ repo }: { repo: ProjectGitStatusItem }) {
  if (!repo.remote) {
    return <p className="gitstatus__note">Not a GitHub repository</p>;
  }
  const github = repo.github;
  if (!github || github.state === "unavailable") {
    return <p className="gitstatus__note">{github?.message ?? "GitHub is unavailable."}</p>;
  }
  if (github.state === "rate-limited") {
    return <p className="gitstatus__note">{github.message ?? "GitHub is rate-limited."}</p>;
  }

  const prs = github.openPullRequests;
  const checks = github.checks;
  // Cap the commit list so the dense report fits its rail panel — three is glanceable and keeps
  // the list from overflowing onto the freshness label below it (NIC-130).
  const commits = (github.recentCommits ?? []).slice(0, 3);

  return (
    <>
      <div className="gitstatus__section">
        <p className="gitstatus__line">
          <span className="gitstatus__label">Open PRs</span>
          <span className="gitstatus__value">{prs?.count ?? 0}</span>
        </p>
        {prs && prs.count > 0 ? (
          <ul className="gitstatus__prs">
            {prs.titles.map((title, index) => (
              <li key={index} className="gitstatus__pr">
                {title}
              </li>
            ))}
          </ul>
        ) : null}
      </div>
      {checks && checks.state !== "none" ? (
        <p className="gitstatus__line">
          <span className="gitstatus__label">CI</span>
          <span className={`gitstatus__checks gitstatus__checks--${checks.state}`}>
            {GITHUB_CHECKS_LABELS[checks.state]}
          </span>
        </p>
      ) : null}
      {commits.length > 0 ? (
        // The commit list is the report's flexible tail: it shows as many rows as fit and clips the
        // rest cleanly (branch/sync/PRs/CI above always stay visible). No header — the SHA chips make
        // the rows self-evidently commits, and dropping it reclaims a line in the dense rail panel.
        <ul className="gitstatus__commits">
          {commits.map((commit) => (
            <li key={commit.shortSha} className="gitstatus__commit">
              <code className="gitstatus__sha">{commit.shortSha}</code>
              <span className="gitstatus__msg">{commit.message}</span>
            </li>
          ))}
        </ul>
      ) : null}
    </>
  );
}

/**
 * The Developer "Project Git Status" widget body (NIC-130): a per-repo report shown one repo at a
 * time, with arrows to swap between repos. The local branch + remote-sync state is read from `.git`
 * and always renders; the GitHub sections come from `GitHubReport`. This is information-dense, so
 * the pager has no autoplay (unlike the releases/stocks carousels). It owns pager state, so it is a
 * component rather than a static `WIDGET_BODIES` entry.
 */
function ProjectGitStatusBody({ items }: { items: readonly ProjectGitStatusItem[] }) {
  const [page, setPage] = useState(0);

  const repoCount = items.length;
  const safePage = Math.min(page, Math.max(0, repoCount - 1));
  const repo = items[safePage];
  if (!repo) return null; // the empty widget state is handled at the slot level; guard anyway

  return (
    <div className="gitstatus">
      {repoCount > 1 ? (
        <div className="gitstatus__pager">
          <button
            type="button"
            className="gitstatus__arrow"
            disabled={safePage === 0}
            aria-label="Previous repository"
            onClick={() => setPage(safePage - 1)}
          >
            ‹
          </button>
          <span className="gitstatus__dots">
            {Array.from({ length: repoCount }).map((_, index) => (
              <span
                key={index}
                className={`gitstatus__dot${index === safePage ? " gitstatus__dot--active" : ""}`}
                aria-hidden="true"
              />
            ))}
          </span>
          <button
            type="button"
            className="gitstatus__arrow"
            disabled={safePage >= repoCount - 1}
            aria-label="Next repository"
            onClick={() => setPage(safePage + 1)}
          >
            ›
          </button>
        </div>
      ) : null}
      <div className="gitstatus__repo">
        <div className="gitstatus__head">
          <span className="repo-row__name">
            <FolderGlyph />
            <span className="repo-row__label">{repo.name}</span>
          </span>
          {repo.branch ? (
            <code className="repo-row__branch">{repo.branch}</code>
          ) : (
            <span className="repo-row__branch repo-row__branch--none" aria-label="no branch">
              —
            </span>
          )}
        </div>
        {repo.sync ? (
          <p className={`gitstatus__sync gitstatus__sync--${repo.sync}`}>
            {GIT_SYNC_LABELS[repo.sync]}
          </p>
        ) : null}
        <GitHubReport repo={repo} />
      </div>
    </div>
  );
}

/** A small line-icon music note for the now-playing artwork placeholder (matches the FolderGlyph
 *  line-icon convention). */
function MusicGlyph() {
  return (
    <svg
      className="nowplaying__note"
      viewBox="0 0 24 24"
      width="22"
      height="22"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M9 17V4l10-2v13" />
      <circle cx="6" cy="17" r="3" />
      <circle cx="16" cy="15" r="3" />
    </svg>
  );
}

/** Playback control glyphs (filled, matching the media aesthetic). */
function PrevIcon() {
  return (
    <svg viewBox="0 0 24 24" width="15" height="15" fill="currentColor" aria-hidden="true">
      <path d="M6 6h2v12H6zM19 6v12L9 12z" />
    </svg>
  );
}
function NextIcon() {
  return (
    <svg viewBox="0 0 24 24" width="15" height="15" fill="currentColor" aria-hidden="true">
      <path d="M16 6h2v12h-2zM5 6l10 6L5 18z" />
    </svg>
  );
}
function PlayIcon() {
  return (
    <svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor" aria-hidden="true">
      <path d="M7 5l12 7-12 7z" />
    </svg>
  );
}
function PauseIcon() {
  return (
    <svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor" aria-hidden="true">
      <path d="M7 5h4v14H7zM13 5h4v14h-4z" />
    </svg>
  );
}

/** The Spotify mark (green circle + sound waves) — a small brand cue on the now-playing card. */
function SpotifyLogo() {
  return (
    <svg
      className="nowplaying__logo"
      viewBox="0 0 24 24"
      width="16"
      height="16"
      aria-label="Spotify"
      role="img"
    >
      <circle cx="12" cy="12" r="12" fill="#1DB954" />
      <g fill="none" stroke="#fff" strokeLinecap="round">
        <path strokeWidth="2.1" d="M6 9c4-1 8-0.5 11.6 1.6" />
        <path strokeWidth="1.7" d="M6.6 12.5c3.2-0.8 6.6-0.4 9.4 1.3" />
        <path strokeWidth="1.4" d="M7.1 15.6c2.5-0.6 5.1-0.3 7.3 1" />
      </g>
    </svg>
  );
}

/** "1:23" from milliseconds — the compact time label for the progress bar. */
function formatTrackTime(ms: number): string {
  const totalSeconds = Math.max(0, Math.floor(ms / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${String(seconds).padStart(2, "0")}`;
}

/**
 * The Entertainment "Spotify" widget body (NIC-133): the track currently playing on Spotify —
 * artwork, track, artist, the active device, a live progress bar, and playback controls (previous /
 * play-pause / next). The progress bar advances smoothly client-side every second while playing and
 * resyncs on each poll, so it stays fluid despite the polling cadence. The controls dispatch the
 * `spotify.control` tool through the command bus (`submitSpotifyControl`); it's honestly
 * `external_write` but the descriptor waives confirmation, so a tap acts at once, and the producer
 * re-polls right after so the track updates near-instantly. Read-only recovery disables the buttons,
 * and a rejected dispatch is surfaced honestly — never a fabricated success.
 */
function SpotifyBody({ track }: { track: SpotifyWidgetPayload }) {
  const bridge = useBridge();
  const { announce } = useActionStatus();
  const { readOnly } = useUiPosture();
  const { reducedMotion } = useAppearance();

  const hasProgress =
    typeof track.progressMs === "number" &&
    typeof track.durationMs === "number" &&
    track.durationMs > 0;

  // Optimistic play/pause: flip the icon/status the instant the user taps, then let the next poll
  // confirm it. Cleared whenever the payload's play state (or the track) changes, so the server
  // stays authoritative. `effectivePlaying` is what the UI shows.
  const [optimisticPlaying, setOptimisticPlaying] = useState<boolean | null>(null);
  useEffect(() => {
    setOptimisticPlaying(null);
  }, [track.isPlaying, track.track]);
  const effectivePlaying = optimisticPlaying ?? track.isPlaying ?? false;

  // Optimistic skip: on next/previous we don't yet know the new track, so show a skeleton until the
  // refresh lands (the track name changes). A safety timeout clears it even if the track repeats.
  const [skipping, setSkipping] = useState(false);
  useEffect(() => {
    setSkipping(false);
  }, [track.track]);
  useEffect(() => {
    if (!skipping) return;
    const id = window.setTimeout(() => setSkipping(false), 2500);
    return () => window.clearTimeout(id);
  }, [skipping]);

  // Anchor the polled position to a local timestamp and advance it every second while playing, so
  // the bar and time move fluidly between polls; each new payload resyncs it. Uses the optimistic
  // play state, so pausing stops the bar at once. Stilled under reduced motion.
  const [displayMs, setDisplayMs] = useState(track.progressMs ?? 0);
  useEffect(() => {
    const base = track.progressMs ?? 0;
    setDisplayMs(base);
    if (!hasProgress || !effectivePlaying || reducedMotion) return;
    const duration = track.durationMs as number;
    const anchor = Date.now();
    const id = window.setInterval(() => {
      setDisplayMs(Math.min(duration, base + (Date.now() - anchor)));
    }, 1000);
    return () => window.clearInterval(id);
  }, [track.progressMs, track.durationMs, effectivePlaying, hasProgress, reducedMotion]);

  const control = (action: SpotifyControlAction, gerund: string) => {
    void submitSpotifyControl(bridge, action)
      .then((receipt) => {
        if (!receipt.accepted) {
          announce(`I couldn't ${gerund} — the command wasn't accepted.`, "error");
        }
      })
      .catch(() => {
        announce(`${gerund} failed — the bridge did not accept it.`, "error");
      });
  };

  const togglePlayPause = () => {
    setOptimisticPlaying(!effectivePlaying); // flip immediately
    if (effectivePlaying) {
      control("pause", "pause playback");
    } else {
      control("play", "resume playback");
    }
  };

  const skip = (action: "next" | "previous", gerund: string) => {
    setSkipping(true); // show the skeleton until the new track lands
    control(action, gerund);
  };

  const openSpotify = () => {
    void submitOpenApp(bridge, "spotify")
      .then((receipt) => {
        if (!receipt.accepted) {
          announce("I couldn't open Spotify — the command wasn't accepted.", "error");
        }
      })
      .catch(() => {
        announce("Opening Spotify failed — the bridge did not accept it.", "error");
      });
  };

  const playPauseLabel = effectivePlaying ? "Pause" : "Play";
  const stateWord = effectivePlaying ? "Playing" : "Paused";
  const statusText = track.deviceName ? `${stateWord} · ${track.deviceName}` : stateWord;
  const percent = hasProgress
    ? Math.min(100, (displayMs / (track.durationMs as number)) * 100)
    : 0;
  const upNextText = track.upNextTrack
    ? track.upNextArtist
      ? `${track.upNextTrack} — ${track.upNextArtist}`
      : track.upNextTrack
    : null;

  return (
    <div className="nowplaying">
      <div className="nowplaying__main">
        <span className="nowplaying__art">
          {skipping ? (
            <SkeletonBone className="nowplaying__art-bone" />
          ) : track.artworkImage ? (
            <img src={track.artworkImage} alt="" loading="lazy" />
          ) : (
            <MusicGlyph />
          )}
        </span>
        <span className="nowplaying__meta">
          {skipping ? (
            <SkeletonBone className="nowplaying__bone nowplaying__bone--track" />
          ) : (
            <span className="nowplaying__track" title={track.track}>
              {track.track}
            </span>
          )}
          {skipping ? (
            <SkeletonBone className="nowplaying__bone nowplaying__bone--artist" />
          ) : (
            <span className="nowplaying__artist" title={track.artist}>
              {track.artist}
            </span>
          )}
          {!skipping && track.album ? <span className="nowplaying__album">{track.album}</span> : null}
          <span
            className={`nowplaying__status nowplaying__status--${effectivePlaying ? "playing" : "paused"}`}
            title={statusText}
          >
            {statusText}
          </span>
        </span>
      </div>
      {skipping ? (
        <div className="nowplaying__progress">
          <SkeletonBone className="nowplaying__bone nowplaying__bone--time" />
          <SkeletonBone className="nowplaying__bone nowplaying__bar-bone" />
          <SkeletonBone className="nowplaying__bone nowplaying__bone--time" />
        </div>
      ) : hasProgress ? (
        <div className="nowplaying__progress">
          <span className="nowplaying__time">{formatTrackTime(displayMs)}</span>
          <span className="nowplaying__bar">
            <span className="nowplaying__bar-fill" style={{ width: `${percent}%` }} />
          </span>
          <span className="nowplaying__time">{formatTrackTime(track.durationMs as number)}</span>
        </div>
      ) : null}
      {!skipping && upNextText ? (
        <p className="nowplaying__upnext" title={upNextText}>
          <span className="nowplaying__upnext-label">Up next</span>
          <span className="nowplaying__upnext-track">{upNextText}</span>
        </p>
      ) : null}
      <span className="nowplaying__controls">
          <button
            type="button"
            className="nowplaying__control"
            disabled={readOnly}
            aria-disabled={readOnly || undefined}
            aria-label="Previous track"
            title={readOnly ? "Controls are paused while the dashboard is read-only" : "Previous track"}
            onClick={() => skip("previous", "go to the previous track")}
          >
            <PrevIcon />
          </button>
          <button
            type="button"
            className="nowplaying__control nowplaying__control--primary"
            disabled={readOnly}
            aria-disabled={readOnly || undefined}
            aria-label={playPauseLabel}
            title={readOnly ? "Controls are paused while the dashboard is read-only" : playPauseLabel}
            onClick={togglePlayPause}
          >
            {effectivePlaying ? <PauseIcon /> : <PlayIcon />}
          </button>
          <button
            type="button"
            className="nowplaying__control"
            disabled={readOnly}
            aria-disabled={readOnly || undefined}
            aria-label="Next track"
            title={readOnly ? "Controls are paused while the dashboard is read-only" : "Next track"}
            onClick={() => skip("next", "skip to the next track")}
          >
            <NextIcon />
          </button>
        </span>
      <button
        type="button"
        className="nowplaying__open"
        disabled={readOnly}
        aria-disabled={readOnly || undefined}
        title={readOnly ? "Opening Spotify is paused while the dashboard is read-only" : "Open Spotify"}
        onClick={openSpotify}
      >
        <SpotifyLogo />
        <span>Open in Spotify</span>
      </button>
    </div>
  );
}

/**
 * The Spotify widget's idle state (NIC-133): when nothing is playing, a "Recently played" list of
 * the last few tracks, each a tappable row that opens Spotify, plus the "Open in Spotify" button.
 * Read-only recovery disables the rows; a rejected dispatch is announced honestly.
 */
function SpotifyRecentBody({ items }: { items: readonly SpotifyRecentTrack[] }) {
  const bridge = useBridge();
  const { announce } = useActionStatus();
  const { readOnly } = useUiPosture();

  const openSpotify = () => {
    void submitOpenApp(bridge, "spotify")
      .then((receipt) => {
        if (!receipt.accepted) {
          announce("I couldn't open Spotify — the command wasn't accepted.", "error");
        }
      })
      .catch(() => {
        announce("Opening Spotify failed — the bridge did not accept it.", "error");
      });
  };

  return (
    <div className="nowplaying nowplaying--recent">
      <ul className="nowplaying__recent">
        {items.map((item, index) => (
          <li key={index} className="nowplaying__recent-item">
            <button
              type="button"
              className="nowplaying__recent-row"
              disabled={readOnly}
              aria-disabled={readOnly || undefined}
              title={readOnly ? "Opening Spotify is paused while the dashboard is read-only" : `Open Spotify — ${item.track}`}
              onClick={openSpotify}
            >
              <MusicGlyph />
              <span className="nowplaying__recent-track">{item.track}</span>
              <span className="nowplaying__recent-artist">{item.artist}</span>
            </button>
          </li>
        ))}
      </ul>
      <button
        type="button"
        className="nowplaying__open"
        disabled={readOnly}
        aria-disabled={readOnly || undefined}
        title={readOnly ? "Opening Spotify is paused while the dashboard is read-only" : "Open Spotify"}
        onClick={openSpotify}
      >
        <SpotifyLogo />
        <span>Open in Spotify</span>
      </button>
    </div>
  );
}

function WidgetBody({ widgetId, data }: { widgetId: string; data: unknown }) {
  // The stocks widget renders a paginated tile grid and owns the reduced-motion hook, so it is
  // dispatched to its own component instead of a pure static renderer (NIC-128).
  if (widgetId === "stocks") {
    const items = (data as { items?: readonly StockQuoteWidgetItem[] })?.items ?? [];
    return <StocksBody items={items} />;
  }
  // The repositories widget renders interactive rows (click-to-open), so it needs runtime
  // hooks and is dispatched to its own component instead of a pure static renderer (NIC-131).
  if (widgetId === "repositories") {
    const items = (data as { items?: readonly RepositoryWidgetItem[] })?.items ?? [];
    return <RepositoriesBody items={items} />;
  }
  // The projects widget likewise renders interactive rows (click-to-expand a detail window).
  if (widgetId === "projects") {
    const items = (data as { items?: readonly ProjectWidgetItem[] })?.items ?? [];
    return <ProjectsBody items={items} />;
  }
  // The releases widget rows click through to a "where to watch" Google search (NIC-134).
  if (widgetId === "releases") {
    const items = (data as { items?: readonly ReleaseWidgetItem[] })?.items ?? [];
    return <ReleasesBody items={items} />;
  }
  // The spotify widget shows the current track (artwork + controls + progress) when playing, or a
  // "Recently played" list to jump back into Spotify when idle (NIC-133).
  if (widgetId === "spotify") {
    const payload = data as SpotifyWidgetPayload | undefined;
    if (payload?.track) return <SpotifyBody track={payload} />;
    if (payload?.recent?.length) return <SpotifyRecentBody items={payload.recent} />;
    return <Unavailable />;
  }
  // The project-git-status widget renders a per-repo report with a repo pager (NIC-130).
  if (widgetId === "project-git-status") {
    const repositories =
      (data as { repositories?: readonly ProjectGitStatusItem[] })?.repositories ?? [];
    return <ProjectGitStatusBody items={repositories} />;
  }
  const render = WIDGET_BODIES[widgetId];
  return render ? <>{render((data ?? {}) as Record<string, unknown>)}</> : <Unavailable />;
}

/**
 * A free-widget slot (left or right). Resolves the widget id to its registry label and body
 * renderer; degraded states (empty / stale / unavailable) render honestly with the freshness
 * indicator (design spec §5.3).
 */
export function WidgetSlot({ data, labelId }: { data: WidgetData; labelId: string }) {
  const label = WIDGET_LABELS.get(data.widgetId) ?? data.widgetId;
  const live = data.state === "ready" || data.state === "stale";

  return (
    <Panel
      label={label}
      labelId={labelId}
      icon={<PanelGlyph name={WIDGET_ICONS[data.widgetId] ?? "widget"} />}
    >
      {live ? (
        <div className="widget">
          {data.state === "stale" ? <StaleMarker /> : null}
          {data.headline ? <p className="widget__headline">{data.headline}</p> : null}
          <WidgetBody widgetId={data.widgetId} data={data.data} />
          {data.freshness ? <p className="widget__freshness">{data.freshness.label}</p> : null}
        </div>
      ) : data.state === "empty" ? (
        // Resolved with no data — a healthy zero-result, not a missing capability.
        <EmptyState label={data.emptyMessage ?? "Nothing to show yet"} />
      ) : (
        <Unavailable label={data.emptyMessage ?? "Unavailable"} />
      )}
    </Panel>
  );
}
