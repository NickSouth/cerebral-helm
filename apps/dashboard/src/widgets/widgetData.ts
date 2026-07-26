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
}

/** The `releases` widget's `data` payload (documented shape for `WidgetData.data`). */
export interface ReleasesWidgetPayload {
  readonly items: readonly ReleaseWidgetItem[];
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
