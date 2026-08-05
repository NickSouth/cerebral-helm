import {
  REPORT_DOCUMENT_SCHEMA_VERSION,
  type ReportBlock,
  type ReportDocument
} from "./reportDocument";
import type { RegionState } from "../bridge/types";

/**
 * `suggest-a-movie` — the Entertainment report, and the third proof of the format.
 *
 * The shortest report of the three: one title, its facts, and a way to look it up. It exists to
 * show that a report is not obliged to be a dashboard — the same renderer draws a five-line
 * document as happily as a grouped schedule.
 *
 * **No relevance filter** (owner decision): the suggestion is drawn from TMDB's trending feed,
 * not from anything about the user. v2 is personalized, which needs a watch-history source that
 * does not exist — so v1 does not pretend to know your taste.
 *
 * TMDB's overview text is not in the releases payload, so the plan's "description" is absent
 * rather than invented.
 */

export interface SuggestibleRelease {
  readonly id: string;
  readonly title: string;
  readonly mediaType: "movie" | "tv";
  readonly year?: number;
}

export interface SuggestAMovieSnapshot {
  readonly now: Date;
  readonly releases: readonly SuggestibleRelease[];
  readonly releasesState: RegionState;
}

/**
 * Which release to suggest. Rotates by calendar day rather than at random: a suggestion that
 * changed on every render would be unusable, and a fixed one would never be a suggestion. Being
 * a pure function of the date also keeps the composer deterministic and testable.
 */
export function suggestionIndex(now: Date, count: number): number {
  if (count <= 0) {
    return -1;
  }
  const startOfYear = Date.UTC(now.getFullYear(), 0, 1);
  const today = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
  const dayOfYear = Math.floor((today - startOfYear) / 86_400_000);
  return dayOfYear % count;
}

export function composeSuggestAMovie(snapshot: SuggestAMovieSnapshot): ReportDocument {
  const blocks: ReportBlock[] = [];
  const index = suggestionIndex(snapshot.now, snapshot.releases.length);
  const pick = index >= 0 ? snapshot.releases[index] : undefined;

  if (snapshot.releasesState === "unavailable") {
    blocks.push({ blockKind: "line", text: "Releases are unavailable.", lineEmphasis: "muted" });
  } else if (!pick) {
    blocks.push({ blockKind: "empty", text: "Nothing new to suggest right now." });
  } else {
    blocks.push({ blockKind: "greeting", text: pick.title, greetingSize: "standard" });
    blocks.push({
      blockKind: "metric",
      label: pick.mediaType === "movie" ? "Film" : "Series",
      // A missing year is omitted, never guessed — TMDB simply doesn't always have one.
      value: pick.year === undefined ? "Release date unknown" : String(pick.year),
      metricTone: "neutral"
    });
    blocks.push({
      blockKind: "proposal",
      text: "Want to know more?",
      // An action REFERENCE, not a URL: the search tool builds the google.com destination
      // host-side, so the title is only ever the query — never the host.
      reportActions: [{ action: "search-the-web", params: { query: pick.title } }]
    });
  }

  return {
    schemaVersion: REPORT_DOCUMENT_SCHEMA_VERSION,
    reportId: "suggest-a-movie",
    blocks
  };
}
