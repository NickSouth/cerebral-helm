import { describe, expect, it } from "vitest";
import {
  courseResult,
  createRow,
  matchesFolder,
  mergeCourses,
  normalizeCourse,
  CREATE_ROW_ID
} from "./takeNotes";
import type { CourseFolder } from "../bridge/cerebralBridge";

/**
 * `take-notes`' course merge (docs/quick-actions/PLAN.md phase 5): Canvas knows what you are
 * enrolled in, the vault knows what you have written in, and neither is the list on its own.
 */

const onDisk: CourseFolder[] = [
  {
    course: "STAT 240",
    folder: "areas/school-umass/STAT 240",
    noteCount: 3,
    updated: "2026-08-03T15:20:00Z"
  }
];

describe("matching a Canvas course to a folder", () => {
  it("matches on the code Canvas gives, and on a name the folder starts", () => {
    expect(matchesFolder({ name: "Probability", code: "STAT 240" }, "STAT 240")).toBe(true);
    expect(
      matchesFolder({ name: "STAT 240 - Introduction to Probability (Fall 2026)" }, "STAT 240")
    ).toBe(true);
    expect(matchesFolder({ name: "stat 240" }, "STAT  240")).toBe(true);
  });

  it("matches a code written without a space, which Canvas does constantly", () => {
    // Found in the browser on the very first render: `CS260` from Canvas beside `CS 260` in the
    // vault rendered the same course twice. The host normalizes the spacing when it names the
    // folder, so the comparison has to as well.
    expect(matchesFolder({ name: "Data Structures", code: "CS260" }, "CS 260")).toBe(true);
    expect(matchesFolder({ name: "CS260" }, "CS 260")).toBe(true);
  });

  it("does not match a different course that merely starts the same way", () => {
    // A false match HIDES a course, which is worse than showing one twice — so the test is narrow,
    // and the space-insensitive comparison is used only for WHOLE-value equality. Compacted,
    // "STAT 2400" starts with "STAT240", which is exactly the trap.
    expect(matchesFolder({ name: "STAT 2400 Advanced" }, "STAT 240")).toBe(false);
    expect(matchesFolder({ name: "STAT 2400 Advanced", code: "STAT2400" }, "STAT 240")).toBe(false);
    expect(matchesFolder({ name: "CS 260" }, "STAT 240")).toBe(false);
  });
});

describe("merging the vault with Canvas", () => {
  it("lists what you have written in first, then what you are enrolled in", () => {
    const merged = mergeCourses(onDisk, [
      { name: "STAT 240 - Probability", code: "STAT 240" },
      { name: "Data Structures", code: "CS 260" }
    ]);

    // The one with notes leads; a Canvas course you have never written in is an invitation.
    expect(merged.map((course) => course.course)).toEqual(["STAT 240", "CS 260"]);
    expect(merged[0].noteCount).toBe(3);
    expect(merged[1].folder).toBeUndefined();
  });

  it("keeps a course whose semester ended and Canvas no longer lists", () => {
    // The reason the vault is a source at all: last term's notes stay reachable.
    expect(mergeCourses(onDisk, []).map((c) => c.course)).toEqual(["STAT 240"]);
  });

  it("prefers Canvas's own code, which is what the host would derive anyway", () => {
    const merged = mergeCourses([], [{ name: "PHIL 100 - Intro to Ethics", code: "PHIL 100" }]);
    expect(merged[0].course).toBe("PHIL 100");
  });

  it("drops a Canvas row with no usable name rather than rendering a blank course", () => {
    expect(mergeCourses([], [{ name: "   " }])).toEqual([]);
  });
});

describe("rendering a course row", () => {
  it("says 'no notes yet' rather than leaving the line blank", () => {
    // A blank second line reads like something failed to load; this is a real state.
    expect(courseResult({ course: "CS 260" }).detail).toBe("No notes yet");
    expect(courseResult({ course: "CS 260", noteCount: 1 }).detail).toBe("1 note");
    expect(courseResult({ course: "CS 260", noteCount: 4 }).detail).toBe("4 notes");
  });
});

describe("the create row", () => {
  it("appears only once something is typed — there is no unnamed thing to create", () => {
    expect(createRow("", "course")).toBeNull();
    expect(createRow("   ", "note")).toBeNull();
  });

  it("names what it will create, and is distinguishable from a result", () => {
    const row = createRow("  Lecture 3  ", "note");
    expect(row?.label).toBe("+ New note “Lecture 3”");
    expect(row?.id.startsWith(CREATE_ROW_ID)).toBe(true);
  });
});

describe("comparing course names", () => {
  it("ignores case and spacing, so one course is never two", () => {
    expect(normalizeCourse("  stat   240 ")).toBe(normalizeCourse("STAT 240"));
  });
});
