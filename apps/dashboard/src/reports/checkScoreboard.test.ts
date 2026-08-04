import { composeCheckScoreboard, selectedEvents, LEADERBOARD_PREVIEW } from "./checkScoreboard";
import { renderableBlocks } from "./reportDocument";
import type { SportsEvent } from "../bridge/cerebralBridge";

/** `check-scoreboard` — the first report opened WITH arguments (quick actions phase 4). */

const game: SportsEvent = {
  id: "nfl-1",
  league: "nfl",
  name: "Carolina Panthers at Arizona Cardinals",
  shortName: "CAR VS ARI",
  state: "in",
  detail: "Q3 5:42",
  venue: "Tom Benson Hall of Fame Stadium · Canton",
  competitors: [
    { abbreviation: "ARI", name: "Arizona Cardinals", score: "17", color: "a40227", isHome: true, record: "1-0" },
    { abbreviation: "CAR", name: "Carolina Panthers", score: "10", color: "0085ca", isHome: false, record: "0-1" }
  ],
  leaderboard: []
};

function tournament(entries: number): SportsEvent {
  return {
    id: "pga-1",
    league: "pga",
    name: "Rocket Classic",
    shortName: "Rocket Classic",
    state: "in",
    detail: "Round 3",
    venue: null,
    competitors: [],
    leaderboard: Array.from({ length: entries }, (_, index) => ({
      order: index + 1,
      position: `T${index + 1}`,
      name: `Player ${index + 1}`,
      score: `-${entries - index}`,
      thru: index === 0 ? "12" : null
    }))
  };
}

function snapshot(overrides: Partial<Parameters<typeof composeCheckScoreboard>[0]> = {}) {
  return composeCheckScoreboard({
    events: [game, tournament(3)],
    selected: ["nfl-1"],
    loading: false,
    reason: null,
    ...overrides
  });
}

describe("check-scoreboard composition", () => {
  it("renders a game as a scoreboard, away side first, with each team's own colour", () => {
    // Away-at-home is how a matchup is read aloud, and the colour arrives in the same payload —
    // which is what lets a scoreboard look like one without fetching a logo.
    const blocks = renderableBlocks(snapshot());
    expect(blocks[0]).toMatchObject({ blockKind: "scoreboard", text: "Q3 5:42" });
    expect(blocks[0].scoreboardSides?.map((side) => side.sideAbbreviation)).toEqual(["CAR", "ARI"]);
    expect(blocks[0].scoreboardSides?.[1]).toMatchObject({ sideScore: "17", sideColor: "a40227" });
  });

  it("shows the venue when the source gave one", () => {
    // NFL supplies a stadium; golf carries no course at all, so this line simply does not appear
    // for a tournament rather than showing a placeholder.
    expect(JSON.stringify(snapshot().blocks)).toContain("Tom Benson Hall of Fame Stadium");
    expect(JSON.stringify(snapshot({ selected: ["pga-1"] }).blocks)).not.toContain("Stadium");
  });

  it("declares itself refreshable, because it came from a fetch", () => {
    // A report composed from ambient state has nothing to re-request and must not offer a control
    // that promises it does.
    expect(snapshot().refreshable).toBe(true);
  });

  it("renders the chosen events in the order they were picked", () => {
    const blocks = renderableBlocks(snapshot({ selected: ["pga-1", "nfl-1"] }));
    expect(JSON.stringify(blocks[0])).toContain("Rocket Classic");
    // The game follows, as a scoreboard rather than a line.
    expect(blocks.some((block) => block.blockKind === "scoreboard")).toBe(true);
    expect(blocks.findIndex((block) => block.blockKind === "scoreboard")).toBeGreaterThan(
      blocks.findIndex((block) => block.blockKind === "leaderboard")
    );
  });

  it("carries the COMPLETE field with a preview count, so expanding needs no second fetch", () => {
    // A block holding only ten rows could not expand at all — and re-reading a megabyte to reveal
    // rows the host already had would be absurd.
    const big = tournament(LEADERBOARD_PREVIEW + 5);
    const document = composeCheckScoreboard({
      events: [big], selected: ["pga-1"], loading: false, reason: null
    });
    const board = renderableBlocks(document).find((block) => block.blockKind === "leaderboard");
    expect(board?.leaderboardRows).toHaveLength(LEADERBOARD_PREVIEW + 5);
    expect(board?.leaderboardPreview).toBe(LEADERBOARD_PREVIEW);
  });

  it("shows `thru` only while a round is in progress", () => {
    const board = renderableBlocks(snapshot({ selected: ["pga-1"] })).find(
      (block) => block.blockKind === "leaderboard"
    );
    // The leader is mid-round; the rest are not, and their row is shorter rather than carrying an
    // empty column.
    expect(board?.leaderboardRows?.[0].rowThru).toBe("12");
    expect(board?.leaderboardRows?.[1].rowThru).toBeUndefined();
  });

  it("distinguishes 'nothing to read' from 'could not read'", () => {
    // Two different facts, and the report says which.
    expect(JSON.stringify(snapshot({ loading: true }).blocks)).toContain("Reading the scores…");
    expect(JSON.stringify(snapshot({ reason: "Couldn't reach nfl." }).blocks)).toContain(
      "Couldn't reach nfl."
    );
  });

  it("says so when a chosen event is no longer listed", () => {
    // A snapshot taken minutes ago can name a game the provider has since rolled off.
    const document = snapshot({ selected: ["gone"] });
    expect(JSON.stringify(document.blocks)).toContain("no longer listed");
  });

  it("skips ids the provider no longer has rather than rendering blanks", () => {
    expect(
      selectedEvents({ events: [game], selected: ["nfl-1", "gone"], loading: false, reason: null })
    ).toEqual([game]);
  });

  it("renders a tournament with no field yet as empty, not as a broken table", () => {
    const document = composeCheckScoreboard({
      events: [tournament(0)], selected: ["pga-1"], loading: false, reason: null
    });
    expect(JSON.stringify(document.blocks)).toContain("No leaderboard yet.");
  });
});
