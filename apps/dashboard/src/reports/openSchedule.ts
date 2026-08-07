import {
  REPORT_DOCUMENT_SCHEMA_VERSION,
  type ReportBlock,
  type ReportDocument
} from "./reportDocument";
import { resolveCourseSchedule, type ResolvableCourse } from "./courseScheduleResolver";
import type { RegionState, ScheduleItem } from "../bridge/types";
import { formatEventTime, formatDay } from "../shell/format";

/**
 * `open-schedule` — the School report, and the second proof that the block format generalizes.
 *
 * Deliberately a very different document from `daily-brief`: it is grouped rather than flat, its
 * list colours carry meaning, and it draws on two providers (Canvas courses joined to the
 * calendar, plus Canvas deadlines). The renderer needed nothing new for any of that, which is the
 * point of the archetype.
 */

export interface ScheduleDeadline {
  readonly id: string;
  readonly title: string;
  readonly dueAt?: string;
  readonly courseName?: string;
}

export interface OpenScheduleSnapshot {
  readonly courses: readonly ResolvableCourse[];
  readonly coursesState: RegionState;
  readonly schedule: {
    readonly state: RegionState;
    readonly items: readonly ScheduleItem[];
  };
  readonly deadlines: readonly ScheduleDeadline[];
  readonly deadlinesState: RegionState;
}

function sectionHeading(text: string): ReportBlock {
  // A `line` with weight, not colour — inside a report colour means actionable, and a heading
  // is not.
  return { blockKind: "line", text, lineEmphasis: "strong" };
}

function classBlocks(snapshot: OpenScheduleSnapshot): ReportBlock[] {
  const { state, items } = snapshot.schedule;

  if (state === "unavailable") {
    return [{ blockKind: "line", text: "Your calendar is unavailable.", lineEmphasis: "muted" }];
  }
  if (items.length === 0) {
    return [{ blockKind: "empty", text: "No classes on the calendar today." }];
  }

  const { groups, ungrouped } = resolveCourseSchedule({
    courses: snapshot.courses,
    items
  });

  const blocks: ReportBlock[] = [];
  for (const group of groups) {
    blocks.push(sectionHeading(group.courseLabel));
    blocks.push({
      blockKind: "list",
      listItems: group.items.map((item) => ({
        text: item.title,
        meta: formatEventTime(item.start) || undefined,
        color: group.color
      }))
    });
  }

  if (ungrouped.length > 0) {
    // Never dropped: an entry the resolver could not attribute still belongs on the schedule.
    blocks.push(sectionHeading("Other"));
    blocks.push({
      blockKind: "list",
      listItems: ungrouped.map((item) => ({
        text: item.title,
        meta: formatEventTime(item.start) || undefined
      }))
    });
  }

  return blocks;
}

function deadlineBlocks(snapshot: OpenScheduleSnapshot): ReportBlock[] {
  // Silence when Canvas was never paired; "unavailable" only when it was and could not be read.
  if (snapshot.deadlinesState === "unavailable") {
    return [
      sectionHeading("Upcoming"),
      { blockKind: "line", text: "Canvas is unavailable.", lineEmphasis: "muted" }
    ];
  }
  if (snapshot.deadlines.length === 0) {
    return [];
  }
  return [
    sectionHeading("Upcoming"),
    {
      blockKind: "list",
      listItems: snapshot.deadlines.map((deadline) => ({
        text: deadline.title,
        meta: formatDay(deadline.dueAt) || undefined
      }))
    }
  ];
}

/** v1: the deterministic join and grouping, in code. */
export function composeOpenSchedule(snapshot: OpenScheduleSnapshot): ReportDocument {
  return {
    schemaVersion: REPORT_DOCUMENT_SCHEMA_VERSION,
    reportId: "open-schedule",
    blocks: [...classBlocks(snapshot), ...deadlineBlocks(snapshot)]
  };
}
