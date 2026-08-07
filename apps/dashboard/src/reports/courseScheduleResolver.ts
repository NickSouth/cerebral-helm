import type { ScheduleItem } from "../bridge/types";

/**
 * Joins Canvas courses to calendar entries for `open-schedule` (docs/quick-actions/PLAN.md).
 *
 * The join key is the **course code, not the course name**. Canvas hands over
 * `STAT 240 - Introduction to Probability and Statistics (Fall 2026)` while a calendar says
 * `STAT 240` or `Stats lecture`; those never string-match, so the resolver extracts a code from
 * both sides and compares that, then falls back to name tokens.
 *
 * Two properties matter more than the matching itself:
 *
 * - **It is deterministic.** No model, no fuzzy scoring that drifts between runs. The same
 *   inputs always produce the same grouping, testable without Canvas or a calendar.
 * - **An unmatched event still renders**, in an ungrouped section. Given fuzzy matching, misses
 *   are certain, and a schedule that silently drops a class is worse than one showing an
 *   unattributed entry.
 */

/** A course as the resolver needs it — the Canvas `courses` widget rows narrowed to the join. */
export interface ResolvableCourse {
  readonly id: string;
  readonly name: string;
  /** Canvas's own short code when it has one; otherwise a code is extracted from `name`. */
  readonly code?: string;
}

export interface CourseScheduleGroup {
  readonly courseId: string;
  readonly courseLabel: string;
  /** Comes from the COURSE, not the calendar: a course whose lecture and final sit on different
   *  calendars must render in one colour, or the grouping defeats itself. */
  readonly color: string;
  readonly items: readonly ScheduleItem[];
}

export interface ResolvedCourseSchedule {
  readonly groups: readonly CourseScheduleGroup[];
  /** Events no rule matched. Rendered, never dropped. */
  readonly ungrouped: readonly ScheduleItem[];
}

/** A course code like `STAT 240` / `CS260`, normalized to `STAT240`. */
const COURSE_CODE = /\b([A-Za-z]{2,4})\s?(\d{3})\b/;

/** Words that carry no course identity, so they can never drive a name-token match. */
const STOPWORDS = new Set([
  "the",
  "and",
  "for",
  "with",
  "introduction",
  "intro",
  "class",
  "lecture",
  "lab",
  "seminar",
  "section",
  "fall",
  "spring",
  "summer",
  "winter",
  "honors",
  "advanced"
]);

/** A small, fixed palette — one stable colour per course. */
const COURSE_COLORS = [
  "#e8b765",
  "#5fd2e8",
  "#a78bfa",
  "#34d399",
  "#f2655e",
  "#f0abfc",
  "#7dd3fc",
  "#fbbf24"
] as const;

export function courseCodeIn(text: string | undefined): string | null {
  if (!text) {
    return null;
  }
  const match = COURSE_CODE.exec(text);
  return match ? `${match[1].toUpperCase()}${match[2]}` : null;
}

function nameTokens(name: string): string[] {
  return name
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((token) => token.length >= 4 && !STOPWORDS.has(token));
}

/**
 * A stable colour per course: derived from the course id, not from its position in the list, so
 * a course keeps its colour when Canvas reorders or a course is added.
 */
export function courseColor(courseId: string): string {
  let hash = 0;
  for (let index = 0; index < courseId.length; index += 1) {
    hash = (hash * 31 + courseId.charCodeAt(index)) >>> 0;
  }
  return COURSE_COLORS[hash % COURSE_COLORS.length];
}

export function resolveCourseSchedule(input: {
  readonly courses: readonly ResolvableCourse[];
  readonly items: readonly ScheduleItem[];
  /**
   * Explicit event-id -> course-id mappings for entries the heuristics cannot catch.
   * Checked **first**: an override that only applied to unmatched events could never correct a
   * wrong match, which is most of what an override is for. Populating this from config is not
   * wired yet — the mechanism is here and tested, the config path is not.
   */
  readonly overrides?: Readonly<Record<string, string>>;
}): ResolvedCourseSchedule {
  const { courses, items, overrides = {} } = input;

  const byId = new Map(courses.map((course) => [course.id, course]));
  const codes = new Map<string, ResolvableCourse>();
  for (const course of courses) {
    const code = courseCodeIn(course.code) ?? courseCodeIn(course.name);
    if (code && !codes.has(code)) {
      codes.set(code, course);
    }
  }

  const grouped = new Map<string, ScheduleItem[]>();
  const ungrouped: ScheduleItem[] = [];

  for (const item of items) {
    const course = matchCourse(item, { byId, codes, courses, overrides });
    if (!course) {
      ungrouped.push(item);
      continue;
    }
    const bucket = grouped.get(course.id);
    if (bucket) {
      bucket.push(item);
    } else {
      grouped.set(course.id, [item]);
    }
  }

  // Course order follows the course list, so the report is stable across renders.
  const groups = courses
    .filter((course) => grouped.has(course.id))
    .map((course) => ({
      courseId: course.id,
      courseLabel: course.code ?? course.name,
      color: courseColor(course.id),
      items: grouped.get(course.id) as ScheduleItem[]
    }));

  return { groups, ungrouped };
}

function matchCourse(
  item: ScheduleItem,
  context: {
    byId: Map<string, ResolvableCourse>;
    codes: Map<string, ResolvableCourse>;
    courses: readonly ResolvableCourse[];
    overrides: Readonly<Record<string, string>>;
  }
): ResolvableCourse | null {
  // 1. An explicit mapping wins outright.
  const override = context.overrides[item.id];
  if (override) {
    const course = context.byId.get(override);
    if (course) {
      return course;
    }
  }

  // 2. Course code on both sides — the reliable join.
  const code = courseCodeIn(item.title);
  if (code) {
    const course = context.codes.get(code);
    if (course) {
      return course;
    }
  }

  // 3. A significant token from the course name appearing in the event title.
  const title = item.title.toLowerCase();
  for (const course of context.courses) {
    if (nameTokens(course.name).some((token) => title.includes(token))) {
      return course;
    }
  }

  return null;
}
