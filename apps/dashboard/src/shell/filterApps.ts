import type { DiscoveredApp } from "../bridge/cerebralBridge";

/**
 * Narrow a discovered-app list to those matching `query` (NIC-167).
 *
 * Plain case-insensitive substring matching, matching the house convention for every other filter
 * in the app (the combobox in `InputRegion`, note search) and the NIC-168 owner decision that
 * command matching stays lexical rather than semantic. No fuzzy scoring: with a list this size a
 * user is completing a name they already know, and a scorer would surface confident-looking wrong
 * answers for a typo instead of an honest empty result.
 *
 * Matches on the display name first and falls back to the bundle id, so `com.apple.` finds Apple's
 * apps and a user who thinks in bundle ids is not stuck. Ordering is preserved — the caller sorted
 * it alphabetically and a filter is not the place to re-rank.
 *
 * An empty or whitespace-only query returns the list unchanged (identity), so callers can pass the
 * raw input without special-casing the initial state.
 */
export function filterApps(
  apps: readonly DiscoveredApp[],
  query: string
): readonly DiscoveredApp[] {
  const needle = query.trim().toLowerCase();
  if (needle.length === 0) {
    return apps;
  }
  return apps.filter(
    (app) =>
      app.name.toLowerCase().includes(needle) || app.bundleId.toLowerCase().includes(needle)
  );
}
