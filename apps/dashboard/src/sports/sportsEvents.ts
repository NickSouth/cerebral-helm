import { useCallback, useEffect, useState } from "react";
import { useBridge } from "../state/BridgeProvider";
import type { CerebralBridge, ListSportsEventsResult, SportsEvent } from "../bridge/cerebralBridge";

/**
 * The shared read behind `check-scoreboard` (quick actions phase 4).
 *
 * **One fetch serves the picker and the report it opens**, because they read the same document —
 * the picker shows the names, the report shows the detail already inside them. Without a cache
 * that would be two round trips per use, and golf's payload is a megabyte the source refuses to
 * narrow (`/leaderboard` 404s, `?limit=` is ignored). So a module-level cache with a short life
 * lets the report reuse what the picker just fetched, while still being a *snapshot* rather than a
 * live feed: past the window it goes back to the source.
 *
 * The window is short on purpose. A cache long enough to hide a score change would make the report
 * quietly wrong, which is worse than slow.
 */

/** How long a fetch is reused. Long enough to span picking games and reading them; no longer. */
export const SPORTS_CACHE_MS = 60_000;

interface CacheEntry {
  readonly at: number;
  readonly promise: Promise<ListSportsEventsResult>;
}

let cache: CacheEntry | null = null;

/**
 * The current events, from cache when it is fresh. `force` bypasses it — what a refresh control
 * calls, and what a test calls to start clean.
 */
export function loadSportsEvents(
  bridge: CerebralBridge,
  options: { force?: boolean; now?: number } = {}
): Promise<ListSportsEventsResult> {
  const now = options.now ?? Date.now();
  if (!options.force && cache && now - cache.at < SPORTS_CACHE_MS) {
    return cache.promise;
  }
  // The *promise* is cached, not its result: the picker and the report open within a moment of
  // each other, so the second caller joins the first request instead of starting a second.
  const promise = bridge.listSportsEvents().catch((error: unknown) => {
    // A failure must not be remembered — the next attempt should be able to succeed.
    cache = null;
    throw error;
  });
  cache = { at: now, promise };
  return promise;
}

/** Drops the cache. For tests, and for a refresh that must not be served from memory. */
export function clearSportsEventsCache(): void {
  cache = null;
}

/** What a consumer sees while and after the read. */
export interface SportsEventsState {
  readonly result: ListSportsEventsResult | null;
  readonly loading: boolean;
  readonly failed: boolean;
  /** Re-reads from the source, bypassing the cache — what a refresh control calls. */
  refresh(): void;
}

/** Reads the events when a surface needs them, and only then. */
export function useSportsEvents(enabled: boolean): SportsEventsState {
  const bridge = useBridge();
  const [state, setState] = useState<Omit<SportsEventsState, "refresh">>({
    result: null,
    loading: enabled,
    failed: false
  });
  // Bumping this re-runs the read with the cache bypassed. A counter rather than a boolean so a
  // second refresh while the first is in flight still triggers a fresh read.
  const [attempt, setAttempt] = useState(0);
  const refresh = useCallback(() => {
    clearSportsEventsCache();
    setAttempt((current) => current + 1);
  }, []);

  useEffect(() => {
    if (!enabled) {
      return;
    }
    let cancelled = false;
    setState((current) => ({ ...current, loading: true }));
    void loadSportsEvents(bridge, { force: attempt > 0 })
      .then((result) => {
        if (!cancelled) {
          setState({ result, loading: false, failed: false });
        }
      })
      .catch(() => {
        if (!cancelled) {
          setState({ result: null, loading: false, failed: true });
        }
      });
    return () => {
      cancelled = true;
    };
  }, [bridge, enabled, attempt]);

  return { ...state, refresh };
}

/** A picker row's label: the matchup or tournament, plus where it is in its life. */
export function eventLabel(event: SportsEvent): string {
  const league = event.league.toUpperCase();
  const detail = event.detail.trim();
  return detail.length > 0
    ? `${league} · ${event.shortName} — ${detail}`
    : `${league} · ${event.shortName}`;
}

/**
 * The events the picker offers, in the order it lists them: anything in progress first, then
 * what is scheduled, then what has finished.
 *
 * Ordering rather than filtering, because "nothing is live right now" is the normal state for
 * most of the year — a picker that hid finished events would be empty all summer, which reads as
 * broken rather than as out of season.
 */
export function pickableEvents(events: readonly SportsEvent[]): readonly SportsEvent[] {
  const rank: Record<string, number> = { in: 0, pre: 1, post: 2 };
  return [...events].sort(
    (a, b) => (rank[a.state] ?? 3) - (rank[b.state] ?? 3) || a.league.localeCompare(b.league)
  );
}
