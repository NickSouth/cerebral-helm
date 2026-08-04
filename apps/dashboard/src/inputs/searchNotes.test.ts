import { describe, expect, it } from "vitest";
import { folderOf, matchesText, mergeNotes, toResult } from "./searchNotes";
import type { NoteListItem, NoteSearchHit } from "../bridge/cerebralBridge";

/**
 * `search-notes`' merge (docs/quick-actions/PLAN.md phase 5): two sources, neither of which is the
 * library on its own.
 */

const listed: NoteListItem[] = [
  {
    path: "projects/atlas/kickoff.md",
    title: "Atlas kickoff",
    folder: "projects/atlas",
    updated: "2026-06-23T18:04:00Z"
  },
  { path: "inbox/Hull Plating.md", title: "Hull Plating", folder: "inbox", updated: null }
];

function hit(overrides: Partial<NoteSearchHit>): NoteSearchHit {
  return { noteId: "ch-note-001", title: "Atlas kickoff", excerpt: "…", ...overrides };
}

describe("matching a listing entry", () => {
  it("matches on title or on the folder the note lives in, case-insensitively", () => {
    expect(matchesText(listed[0], "ATLAS")).toBe(true); // title
    expect(matchesText(listed[0], "projects/")).toBe(true); // folder
    expect(matchesText(listed[0], "rivets")).toBe(false); // body — the index's job, not this
  });
});

describe("merging the file listing with the index", () => {
  it("keeps the listing's display and gains the index's excerpt for a note found by both", () => {
    const hits = [hit({ path: "projects/atlas/kickoff.md", excerpt: "scope and owners" })];
    const merged = mergeNotes(listed, hits, new Map([[hits[0].path!, hits[0].excerpt]]));

    expect(merged).toHaveLength(2);
    // The folder and date survive (the index knows neither) and the excerpt is added, so a body
    // match can say WHY it matched without losing WHERE it lives.
    expect(merged[0]).toMatchObject({
      path: "projects/atlas/kickoff.md",
      folder: "projects/atlas",
      updated: "2026-06-23T18:04:00Z",
      excerpt: "scope and owners"
    });
  });

  it("appends a note only the index found, deriving its folder from the path", () => {
    const hits = [hit({ path: "areas/health/sleep.md", title: "Sleep", excerpt: "eight hours" })];
    const merged = mergeNotes([], hits, new Map());

    expect(merged).toHaveLength(1);
    expect(merged[0]).toMatchObject({ folder: "areas/health", excerpt: "eight hours" });
  });

  it("never lists the same note twice, however both sources found it", () => {
    const hits = [hit({ path: "projects/atlas/kickoff.md" }), hit({ path: "inbox/Hull Plating.md" })];
    const merged = mergeNotes(listed, hits, new Map());

    expect(merged.map((note) => note.path)).toEqual([
      "projects/atlas/kickoff.md",
      "inbox/Hull Plating.md"
    ]);
  });

  it("drops a hit with no path — a row that would fail on click is worse than no row", () => {
    // The index is derived state and can lag the files; without a path there is nothing to open.
    const merged = mergeNotes([], [hit({ path: undefined })], new Map());
    expect(merged).toEqual([]);
  });
});

describe("rendering a row", () => {
  it("prefers the excerpt over the folder as the second line — why it matched beats where it is", () => {
    expect(toResult({ ...listed[0], excerpt: "scope and owners" }).detail).toBe("scope and owners");
    expect(toResult(listed[0]).detail).toBe("projects/atlas");
  });

  it("opens by path, so the id a row carries is the handle the host resolves", () => {
    expect(toResult(listed[0]).id).toBe("projects/atlas/kickoff.md");
  });

  it("shows no date rather than an invalid one", () => {
    expect(toResult({ ...listed[0], updated: "not a date" }).meta).toBeUndefined();
    expect(toResult(listed[1]).meta).toBeUndefined();
  });

  it("reads a root-level note as living in no folder, not in a folder called empty", () => {
    expect(folderOf("README.md")).toBe("");
    expect(folderOf("areas/school-umass/STAT 240/lecture.md")).toBe("areas/school-umass/STAT 240");
  });
});
