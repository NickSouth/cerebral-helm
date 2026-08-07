import { composeOpenSchedule, type OpenScheduleSnapshot } from "./openSchedule";
import { composeSuggestAMovie, suggestionIndex, type SuggestAMovieSnapshot } from "./suggestAMovie";
import { isRenderable, type ReportBlock } from "./reportDocument";

/**
 * The two reports that prove the block format generalizes: a grouped, two-provider schedule and a
 * five-line suggestion. Neither needed a renderer change, which is the claim being tested here as
 * much as the formulas themselves.
 */

function kinds(blocks: readonly ReportBlock[]): string[] {
  return blocks.map((block) => block.blockKind);
}

function texts(blocks: readonly ReportBlock[]): (string | undefined)[] {
  return blocks.map((block) => block.text);
}

// --- open-schedule --------------------------------------------------------

function scheduleSnapshot(overrides: Partial<OpenScheduleSnapshot> = {}): OpenScheduleSnapshot {
  return {
    courses: [
      { id: "c1", name: "Probability and Statistics", code: "STAT 240" },
      { id: "c2", name: "Organic Chemistry I", code: "CHEM 261" }
    ],
    coursesState: "ready",
    schedule: {
      state: "ready",
      items: [
        { id: "e1", title: "STAT 240", start: "2026-08-03T14:00:00", kind: "today" },
        { id: "e2", title: "CHEM 261 Lab", start: "2026-08-03T16:00:00", kind: "today" },
        { id: "e3", title: "Dentist", start: "2026-08-03T18:00:00", kind: "today" }
      ]
    },
    deadlines: [{ id: "d1", title: "Problem set 4", dueAt: "2026-08-05T23:59:00" }],
    deadlinesState: "ready",
    ...overrides
  };
}

describe("composeOpenSchedule", () => {
  it("groups classes by course, each under its own heading", () => {
    const document = composeOpenSchedule(scheduleSnapshot());
    expect(document.reportId).toBe("open-schedule");
    // heading + list per course, then the unmatched section, then deadlines.
    expect(kinds(document.blocks)).toEqual([
      "line",
      "list",
      "line",
      "list",
      "line",
      "list",
      "line",
      "list"
    ]);
    expect(texts(document.blocks).filter(Boolean)).toEqual([
      "STAT 240",
      "CHEM 261",
      "Other",
      "Upcoming"
    ]);
  });

  it("keeps an unattributed event under 'Other' instead of dropping it", () => {
    const document = composeOpenSchedule(scheduleSnapshot());
    const otherIndex = document.blocks.findIndex((block) => block.text === "Other");
    expect(document.blocks[otherIndex + 1].listItems?.map((item) => item.text)).toEqual(["Dentist"]);
  });

  it("colours grouped items by course and leaves ungrouped ones uncoloured", () => {
    const document = composeOpenSchedule(scheduleSnapshot());
    const [, firstList] = document.blocks;
    expect(firstList.listItems?.[0].color).toBeTruthy();

    const otherIndex = document.blocks.findIndex((block) => block.text === "Other");
    expect(document.blocks[otherIndex + 1].listItems?.[0].color).toBeUndefined();
  });

  it("uses weight, not colour, for section headings", () => {
    // Inside a report colour means actionable, and a heading is not.
    const document = composeOpenSchedule(scheduleSnapshot());
    for (const block of document.blocks.filter((candidate) => candidate.blockKind === "line")) {
      expect(block.lineEmphasis).toBe("strong");
    }
  });

  it("distinguishes an empty calendar from an unreadable one", () => {
    const empty = composeOpenSchedule(
      scheduleSnapshot({ schedule: { state: "ready", items: [] }, deadlines: [] })
    );
    expect(kinds(empty.blocks)).toEqual(["empty"]);
    expect(empty.blocks[0].text).toBe("No classes on the calendar today.");

    const broken = composeOpenSchedule(
      scheduleSnapshot({ schedule: { state: "unavailable", items: [] }, deadlines: [] })
    );
    expect(broken.blocks[0].text).toBe("Your calendar is unavailable.");
    expect(broken.blocks[0].lineEmphasis).toBe("muted");
  });

  it("says nothing about deadlines it has none of, and 'unavailable' when Canvas failed", () => {
    const none = composeOpenSchedule(scheduleSnapshot({ deadlines: [] }));
    expect(texts(none.blocks)).not.toContain("Upcoming");

    const failed = composeOpenSchedule(
      scheduleSnapshot({ deadlines: [], deadlinesState: "unavailable" })
    );
    expect(failed.blocks.at(-1)?.text).toBe("Canvas is unavailable.");
  });

  it("emits only blocks the renderer can draw", () => {
    for (const block of composeOpenSchedule(scheduleSnapshot()).blocks) {
      expect(isRenderable(block)).toBe(true);
    }
  });
});

// --- suggest-a-movie ------------------------------------------------------

function movieSnapshot(overrides: Partial<SuggestAMovieSnapshot> = {}): SuggestAMovieSnapshot {
  return {
    now: new Date("2026-08-03T20:00:00"),
    releases: [
      { id: "m1", title: "Dune: Part Two", mediaType: "movie", year: 2024 },
      { id: "t1", title: "The Bear", mediaType: "tv", year: 2024 },
      { id: "m2", title: "Nosferatu", mediaType: "movie" }
    ],
    releasesState: "ready",
    ...overrides
  };
}

describe("composeSuggestAMovie", () => {
  it("suggests one title with its facts and a way to look it up", () => {
    const document = composeSuggestAMovie(movieSnapshot());
    expect(document.reportId).toBe("suggest-a-movie");
    expect(kinds(document.blocks)).toEqual(["greeting", "metric", "proposal"]);
  });

  it("rotates by day, so it is stable within a day and different across days", () => {
    const on = (iso: string) => composeSuggestAMovie(movieSnapshot({ now: new Date(iso) })).blocks[0].text;
    expect(on("2026-08-03T09:00:00")).toBe(on("2026-08-03T23:00:00"));
    expect(on("2026-08-03T09:00:00")).not.toBe(on("2026-08-04T09:00:00"));
  });

  it("wraps the rotation and handles an empty feed without dividing by zero", () => {
    expect(suggestionIndex(new Date("2026-08-03T09:00:00"), 3)).toBeGreaterThanOrEqual(0);
    expect(suggestionIndex(new Date("2026-08-03T09:00:00"), 3)).toBeLessThan(3);
    expect(suggestionIndex(new Date("2026-08-03T09:00:00"), 0)).toBe(-1);
  });

  it("says the release date is unknown rather than guessing one", () => {
    const document = composeSuggestAMovie(
      movieSnapshot({ releases: [{ id: "m2", title: "Nosferatu", mediaType: "movie" }] })
    );
    expect(document.blocks[1].value).toBe("Release date unknown");
  });

  it("links out as an action REFERENCE carrying the title as a param, never as a URL", () => {
    // The search tool builds the google.com destination host-side, so a model-chosen title is
    // only ever the query.
    const document = composeSuggestAMovie(movieSnapshot());
    const proposal = document.blocks.find((block) => block.blockKind === "proposal");
    expect(proposal?.reportActions).toHaveLength(1);
    expect(proposal?.reportActions?.[0].action).toBe("search-the-web");
    expect(proposal?.reportActions?.[0].params).toEqual({ query: document.blocks[0].text });
  });

  it("distinguishes an empty feed from an unavailable one", () => {
    const empty = composeSuggestAMovie(movieSnapshot({ releases: [] }));
    expect(kinds(empty.blocks)).toEqual(["empty"]);

    const failed = composeSuggestAMovie(movieSnapshot({ releases: [], releasesState: "unavailable" }));
    expect(failed.blocks[0].text).toBe("Releases are unavailable.");
    expect(failed.blocks[0].lineEmphasis).toBe("muted");
  });
});
