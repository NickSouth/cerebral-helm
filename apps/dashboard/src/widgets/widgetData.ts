/**
 * Common widget-data envelope. Design spec §5.3: each widget surfaces its own data,
 * an empty state, a freshness indicator, and an optional action — a named slot, not a
 * per-mode conditional. The per-widget payload under `data` is widget-specific and
 * demonstrated by the fixtures in ./fixtures/widgetData.fixtures.json.
 *
 * This envelope is the shape NIC-52 (the expanded DashboardBootstrapState, NIC-117 d)
 * lifts so the bridge can deliver widget data across the boundary. Pre-bridge it backs
 * the fixture-rendered widget slots in NIC-54.
 */

import type { WidgetId } from "./widgets";

export type WidgetState = "ready" | "empty" | "stale" | "unavailable";

export interface WidgetFreshness {
  /** ISO-8601 instant the data was observed. */
  readonly observedAt: string;
  /** Short human label, e.g. "2m ago". */
  readonly label: string;
}

export interface WidgetAction {
  readonly id: string;
  readonly label: string;
}

export interface WidgetData<TPayload = unknown> {
  readonly widgetId: WidgetId;
  readonly state: WidgetState;
  /** Present when state is "ready" (and may accompany "stale"). */
  readonly headline?: string;
  /** Widget-specific payload; shape demonstrated by the fixtures. */
  readonly data?: TPayload;
  readonly freshness?: WidgetFreshness;
  /** Shown when state is "empty" or "unavailable" — an honest, specific message. */
  readonly emptyMessage?: string;
  readonly action?: WidgetAction;
}

/**
 * One ticker in the `stocks` widget's payload (NIC-128, Executive left slot). `price`,
 * `change`, and `changePercent` are the day-status figures the tile shows; each is omitted
 * (never fabricated) when the provider can't resolve the symbol — the tile then renders a
 * muted "—" for that field. `symbol` is the stable row key. This documents the shape the
 * live producer will stream (a later increment); pre-bridge it backs the fixture tiles.
 */
export interface StockQuoteWidgetItem {
  readonly symbol: string;
  /** Current price. Omitted when the quote couldn't be resolved. */
  readonly price?: number;
  /** Absolute price change on the day (vs previous close). Omitted when unknown. */
  readonly change?: number;
  /** Percent price change on the day. Omitted when unknown. */
  readonly changePercent?: number;
  /** Recent daily closes (oldest → newest, ~1 month) for the tile's sparkline. Best-effort and
   *  decorative — omitted when no history was resolved, and the tile then shows no line. */
  readonly history?: readonly number[];
}

/** The `stocks` widget's `data` payload (documented shape for `WidgetData.data`). */
export interface StocksWidgetPayload {
  readonly items: readonly StockQuoteWidgetItem[];
}

/**
 * One repository row in the `repositories` widget's payload (NIC-131). `branch` is omitted
 * when the local repo's HEAD can't be resolved (never fabricated); `path` is the absolute
 * repo directory the click-to-open action targets (Increment 6). This documents the shape
 * the live producer streams under `WidgetData.data`; the render dispatch in WidgetSlot reads
 * this slice.
 */
export interface RepositoryWidgetItem {
  readonly id: string;
  readonly name: string;
  readonly branch?: string;
  readonly path: string;
}

/** The `repositories` widget's `data` payload (documented shape for `WidgetData.data`). */
export interface RepositoriesWidgetPayload {
  readonly items: readonly RepositoryWidgetItem[];
}

/**
 * One project row in the `projects` widget's payload (NIC-129), in most-important-first order
 * (the native reader sorts by each project's `PROJECT.md` `importance`, then recency).
 * `descriptorPath` is omitted when the project has no `PROJECT.md`; `hasDescriptor` is the
 * honest gate the row uses to enable/disable click-to-expand (Increment 6). This documents
 * the shape the live producer streams under `WidgetData.data`.
 */
export interface ProjectWidgetItem {
  readonly id: string;
  readonly name: string;
  readonly path: string;
  readonly descriptorPath?: string;
  readonly hasDescriptor: boolean;
}

/** The `projects` widget's `data` payload (documented shape for `WidgetData.data`). */
export interface ProjectsWidgetPayload {
  readonly items: readonly ProjectWidgetItem[];
}

/**
 * One release row in the `releases` widget's payload (NIC-134, Entertainment right slot): a
 * new/hot movie or TV show from TMDB. `year` is omitted when the release date is unknown
 * (never fabricated); `id` is the TMDB id, used as the stable row key. This documents the
 * shape the live producer will stream (Increment 5); pre-bridge it backs the fixture rows.
 */
export interface ReleaseWidgetItem {
  readonly id: string;
  readonly title: string;
  readonly mediaType: "movie" | "tv";
  readonly year?: number;
  /** Poster artwork as a self-contained `data:` URI (base64), fetched natively by the producer
   *  (NIC-134) because the dashboard origin does not load external image URLs. Absent when the
   *  release has no poster or it couldn't be fetched — the card shows a title placeholder. */
  readonly posterImage?: string;
}

/** The `releases` widget's `data` payload (documented shape for `WidgetData.data`). */
export interface ReleasesWidgetPayload {
  readonly items: readonly ReleaseWidgetItem[];
}

/**
 * The `spotify` widget's `data` payload (NIC-133, Entertainment left slot): the track currently
 * playing on Spotify. Present only when the widget state is `ready` — nothing playing is a healthy
 * `empty` state and not-connected is `unavailable`, both handled at the slot level, so a `ready`
 * payload always carries a track. `album` and `artworkImage` are omitted (never fabricated) when
 * Spotify doesn't provide them; `artworkImage` is a self-contained `data:` URI fetched natively by
 * the producer (a later increment) because the dashboard origin does not load external image URLs.
 * `isPlaying` distinguishes actively playing from paused — a paused track is still the current one.
 */
/** A recently-played track shown in the idle "jump back in" list (NIC-133). */
export interface SpotifyRecentTrack {
  readonly track: string;
  readonly artist: string;
}

export interface SpotifyWidgetPayload {
  /** The current track — absent in the idle "recently played" state (then `recent` is populated). */
  readonly track?: string;
  readonly artist?: string;
  readonly album?: string;
  readonly artworkImage?: string;
  readonly isPlaying?: boolean;
  /** The active Spotify device's name (e.g. "Nick's MacBook Pro"), omitted when unknown. */
  readonly deviceName?: string;
  /** Playback position within the track, in milliseconds — with `durationMs`, drives the progress
   *  bar (which the widget advances smoothly between polls). Omitted when unknown. */
  readonly progressMs?: number;
  /** Track length in milliseconds. Omitted when unknown. */
  readonly durationMs?: number;
  /** The next queued track's title (the "Up next" line), omitted when the queue is empty/unknown. */
  readonly upNextTrack?: string;
  /** The next queued track's artist, omitted when unknown. */
  readonly upNextArtist?: string;
  /** Recently-played tracks — populated only in the idle state (no current track) for the "jump
   *  back in" list. */
  readonly recent?: readonly SpotifyRecentTrack[];
}

/**
 * The local branch's relationship to its `origin` remote-tracking ref (NIC-130), derived from
 * comparing ref SHAs in `.git` — never a numeric count. `synced` = the local tip equals
 * `origin/<branch>`; `diverged` = they differ (direction is deliberately not claimed, since that
 * needs a commit-graph walk); `no-upstream` = there is no `origin/<branch>` (an unpushed branch).
 * This reflects the last local fetch, not the live remote.
 */
export type GitSyncState = "synced" | "diverged" | "no-upstream";

/**
 * The collapsed CI state for a repo's latest commit (NIC-130). `none` is a first-class, tidy
 * state — the repo simply has no CI — and the widget omits the CI line entirely rather than
 * showing an error or an empty slot. It is distinct from the GitHub section being `unavailable`
 * or `rate-limited` (a reachability problem), which is surfaced honestly instead.
 */
export type GitHubChecksState = "passing" | "failing" | "pending" | "none";

/** Whether the GitHub half of a repo's report could be read (NIC-130). `ready` = the PR/CI/commit
 *  fields are populated; `unavailable`/`rate-limited` carry an honest `message` instead. */
export type ProjectGitHubState = "ready" | "unavailable" | "rate-limited";

/** One recent commit line in a repo's GitHub report (NIC-130). */
export interface ProjectGitCommit {
  readonly message: string;
  readonly shortSha: string;
}

/**
 * The GitHub half of a repo's report (NIC-130), present only when the repo has a GitHub remote.
 * When `state` is `ready`, the PR/checks/commit fields are populated (each omitted, never
 * fabricated, when GitHub returned nothing for it); otherwise `message` explains the honest
 * unavailable/rate-limited state.
 */
export interface ProjectGitHubReport {
  readonly state: ProjectGitHubState;
  readonly openPullRequests?: { readonly count: number; readonly titles: readonly string[] };
  readonly checks?: { readonly state: GitHubChecksState };
  readonly recentCommits?: readonly ProjectGitCommit[];
  /** Shown when `state` is `unavailable` or `rate-limited` — an honest, specific message. */
  readonly message?: string;
}

/**
 * One repository in the `project-git-status` widget's payload (NIC-130, Developer left slot). The
 * local fields (`branch`, `sync`) are read directly from `.git` and always render; `remote` is the
 * resolved GitHub `owner/repo` (omitted when `origin` is not a GitHub remote — the repo then shows
 * local data only); `github` is the read-only GitHub REST report (omitted when there is no remote,
 * and carrying its own honest state when GitHub is unreachable). The widget shows one repo at a
 * time, and the render dispatch pages between them.
 */
export interface ProjectGitStatusItem {
  readonly id: string;
  readonly name: string;
  readonly branch?: string;
  readonly sync?: GitSyncState;
  readonly remote?: { readonly owner: string; readonly repo: string };
  readonly github?: ProjectGitHubReport;
}

/** The `project-git-status` widget's `data` payload (documented shape for `WidgetData.data`). */
export interface ProjectGitStatusWidgetPayload {
  readonly repositories: readonly ProjectGitStatusItem[];
}

/**
 * Resolve the WidgetData a rail slot renders: the live-streamed value for `widgetId`
 * (NIC-131 blueprint) when a producer has delivered one, else the bootstrap/config value.
 * `liveWidgets` is runtime-only state keyed by widget id and lives outside `regions`, so
 * this resolution survives `config.changed` mode switches by construction — every future
 * live widget inherits it without touching the mode-switch reducer path.
 */
export function resolveWidgetData(
  liveWidgets: Readonly<Record<string, WidgetData>> | undefined,
  widgetId: string,
  fallback: WidgetData
): WidgetData {
  return liveWidgets?.[widgetId] ?? fallback;
}
