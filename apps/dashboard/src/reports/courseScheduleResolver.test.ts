import {
  courseCodeIn,
  courseColor,
  resolveCourseSchedule,
  type ResolvableCourse
} from "./courseScheduleResolver";
import type { ScheduleItem } from "../bridge/types";

const COURSES: ResolvableCourse[] = [
  { id: "c1", name: "Introduction to Probability and Statistics (Fall 2026)", code: "STAT 240" },
  { id: "c2", name: "Organic Chemistry I", code: "CHEM 261" },
  { id: "c3", name: "Medieval European History" }
];

function event(id: string, title: string, start = "2026-08-03T14:00:00"): ScheduleItem {
  return { id, title, start, kind: "today" };
}

describe("courseCodeIn", () => {
  it("extracts a normalized course code from either side's free text", () => {
    expect(courseCodeIn("STAT 240 - Introduction to Probability")).toBe("STAT240");
    expect(courseCodeIn("stat240 lecture")).toBe("STAT240");
    expect(courseCodeIn("CHEM 261 Lab")).toBe("CHEM261");
    expect(courseCodeIn("Lunch with Dana")).toBeNull();
    expect(courseCodeIn(undefined)).toBeNull();
  });
});

describe("resolveCourseSchedule", () => {
  it("joins on the course CODE, which is what actually matches across the two sources", () => {
    // Canvas says "Introduction to Probability and Statistics (Fall 2026)"; the calendar says
    // "STAT 240". Those never string-match — the code is the join.
    const { groups, ungrouped } = resolveCourseSchedule({
      courses: COURSES,
      items: [event("e1", "STAT 240"), event("e2", "CHEM 261 Lab")]
    });

    expect(ungrouped).toEqual([]);
    expect(groups.map((group) => group.courseId)).toEqual(["c1", "c2"]);
    expect(groups[0].items.map((item) => item.id)).toEqual(["e1"]);
  });

  it("falls back to a significant name token when neither side carries a code", () => {
    const { groups } = resolveCourseSchedule({
      courses: COURSES,
      items: [event("e1", "Medieval seminar")]
    });
    expect(groups).toHaveLength(1);
    expect(groups[0].courseId).toBe("c3");
  });

  it("never matches on a generic word", () => {
    // "Lecture" and "Fall" appear in course names but identify nothing.
    const { groups, ungrouped } = resolveCourseSchedule({
      courses: COURSES,
      items: [event("e1", "Lecture"), event("e2", "Fall planning")]
    });
    expect(groups).toEqual([]);
    expect(ungrouped.map((item) => item.id)).toEqual(["e1", "e2"]);
  });

  it("renders an unmatched event rather than dropping it", () => {
    // Misses are certain with fuzzy matching, and a schedule that silently loses a class is
    // worse than one showing an unattributed entry.
    const { groups, ungrouped } = resolveCourseSchedule({
      courses: COURSES,
      items: [event("e1", "STAT 240"), event("e2", "Dentist")]
    });
    expect(groups).toHaveLength(1);
    expect(ungrouped.map((item) => item.title)).toEqual(["Dentist"]);
  });

  it("lets an explicit override win over the heuristics", () => {
    // An override that only applied to unmatched events could never correct a WRONG match,
    // which is most of what an override is for.
    const { groups } = resolveCourseSchedule({
      courses: COURSES,
      items: [event("e1", "STAT 240")],
      overrides: { e1: "c2" }
    });
    expect(groups.map((group) => group.courseId)).toEqual(["c2"]);
  });

  it("ignores an override naming a course that does not exist", () => {
    const { groups } = resolveCourseSchedule({
      courses: COURSES,
      items: [event("e1", "STAT 240")],
      overrides: { e1: "not-a-course" }
    });
    expect(groups.map((group) => group.courseId)).toEqual(["c1"]);
  });

  it("is deterministic — same inputs, same grouping and colours", () => {
    const input = { courses: COURSES, items: [event("e1", "STAT 240"), event("e2", "Dentist")] };
    expect(resolveCourseSchedule(input)).toEqual(resolveCourseSchedule(input));
  });

  it("colours by course, so one course is one colour wherever its events came from", () => {
    const { groups } = resolveCourseSchedule({
      courses: COURSES,
      // Two STAT 240 entries that could plausibly sit on different calendars.
      items: [event("e1", "STAT 240 lecture"), event("e2", "STAT 240 final")]
    });
    expect(groups).toHaveLength(1);
    expect(groups[0].color).toBe(courseColor("c1"));
  });

  it("keeps a course's colour stable when the course list is reordered", () => {
    const forward = resolveCourseSchedule({ courses: COURSES, items: [event("e1", "STAT 240")] });
    const reversed = resolveCourseSchedule({
      courses: [...COURSES].reverse(),
      items: [event("e1", "STAT 240")]
    });
    expect(reversed.groups[0].color).toBe(forward.groups[0].color);
  });
});
