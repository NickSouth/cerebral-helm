import {
  REPORT_DOCUMENT_SCHEMA_VERSION,
  type ReportBlock,
  type ReportDocument
} from "./reportDocument";
import type { SportsEvent } from "../bridge/cerebralBridge";

/**
 * `check-scoreboard` — the first action that is an **Input and a Report**: a picker of up to three
 * events, then a composed report of the ones chosen (quick actions phase 4).
 *
 * That combination is why reports became parameterizable. Every other report reads ambient
 * dashboard state, so its id was the whole request; here *which games* is the user's answer and
 * has to travel with the open.
 *
 * It renders through two block kinds added for it — `scoreboard` and `leaderboard` — which is
 * exactly the additive change the flat block shape exists to absorb. The leaderboard carries the
 * COMPLETE field with a preview count, so expanding to everyone is a render decision rather than a
 * second megabyte.
 */

/** How many leaderboard rows show before the reader expands to the full field. */
export const LEADERBOARD_PREVIEW = 10;

export interface CheckScoreboardSnapshot {
  /** Everything the provider returned; the report picks its own out of it. */
  readonly events: readonly SportsEvent[];
  /** The ids the user chose, in the order the picker offered them. */
  readonly selected: readonly string[];
  readonly loading: boolean;
  /** Why the read failed, when it did — distinct from "nothing is on today". */
  readonly reason: string | null;
}

/** The chosen events, in the order they were selected, skipping any the provider no longer has. */
export function selectedEvents(snapshot: CheckScoreboardSnapshot): readonly SportsEvent[] {
  return snapshot.selected
    .map((id) => snapshot.events.find((event) => event.id === id))
    .filter((event): event is SportsEvent => event !== undefined);
}

/**
 * A team game as a `scoreboard` block: away first, each side with its own colour.
 *
 * The status is passed through rather than re-worded — "Final", "Q3 5:42" and "8/6 - 8:00 PM EDT"
 * are already how a viewer expects to read them, and re-composing them here would be an
 * opportunity to be wrong about a sport's conventions. The venue rides along on its own line when
 * the provider gave one, which it does for NFL and does not for golf.
 */
function gameBlocks(event: SportsEvent): ReportBlock[] {
  const away = event.competitors.find((side) => !side.isHome);
  const home = event.competitors.find((side) => side.isHome);
  if (!away || !home) {
    // Not two sides: fall back to the line the picker showed rather than half a scoreboard.
    return [{ blockKind: "line", text: `${event.shortName} — ${event.detail}`, lineEmphasis: "normal" }];
  }
  const blocks: ReportBlock[] = [
    {
      blockKind: "scoreboard",
      text: event.detail || undefined,
      scoreboardSides: [away, home].map((side) => ({
        sideAbbreviation: side.abbreviation,
        sideName: side.name,
        sideScore: side.score,
        sideColor: side.color ?? undefined,
        sideIsHome: side.isHome,
        sideRecord: side.record ?? undefined
      }))
    }
  ];
  if (event.venue) {
    blocks.push({ blockKind: "line", text: event.venue, lineEmphasis: "muted" });
  }
  return blocks;
}

/** A tournament: a heading line and the top of the field. */
function tournamentBlocks(event: SportsEvent): ReportBlock[] {
  const blocks: ReportBlock[] = [
    {
      blockKind: "line",
      text: `${event.name} — ${event.detail || "—"}`,
      lineEmphasis: "normal"
    }
  ];
  if (event.leaderboard.length === 0) {
    // A tournament with no field yet is a real state before the first round, and says so rather
    // than rendering an empty table.
    blocks.push({ blockKind: "empty", text: "No leaderboard yet." });
    return blocks;
  }
  // The COMPLETE field, with a preview count — expanding is then a render decision rather than a
  // second megabyte. A block holding only ten rows could not expand at all.
  blocks.push({
    blockKind: "leaderboard",
    leaderboardPreview: LEADERBOARD_PREVIEW,
    leaderboardRows: event.leaderboard.map((entry) => ({
      rowPosition: entry.position ?? undefined,
      rowName: entry.name,
      rowScore: entry.score,
      // `thru` only exists mid-round, so its absence shortens the row instead of printing a dash.
      rowThru: entry.thru ?? undefined
    }))
  });
  return blocks;
}

export function composeCheckScoreboard(snapshot: CheckScoreboardSnapshot): ReportDocument {
  const blocks: ReportBlock[] = [];

  if (snapshot.loading) {
    blocks.push({ blockKind: "line", text: "Reading the scores…", lineEmphasis: "muted" });
  } else if (snapshot.reason) {
    // Unreadable and empty are different facts, and the report says which.
    blocks.push({ blockKind: "line", text: snapshot.reason, lineEmphasis: "muted" });
  } else {
    const chosen = selectedEvents(snapshot);
    if (chosen.length === 0) {
      blocks.push({ blockKind: "empty", text: "Those games are no longer listed." });
    }
    for (const event of chosen) {
      blocks.push(
        ...(event.competitors.length > 0 ? gameBlocks(event) : tournamentBlocks(event))
      );
    }
  }

  return {
    schemaVersion: REPORT_DOCUMENT_SCHEMA_VERSION,
    reportId: "check-scoreboard",
    blocks,
    // Composed from a fetch, so the reader can repeat it — the snapshot semantics this action was
    // designed around, made visible as a control rather than left implicit.
    refreshable: true
  };
}
