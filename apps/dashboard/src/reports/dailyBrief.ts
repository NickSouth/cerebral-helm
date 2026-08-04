import {
  REPORT_DOCUMENT_SCHEMA_VERSION,
  type ReportBlock,
  type ReportDocument
} from "./reportDocument";
import type { RegionState, ScheduleItem } from "../bridge/types";
import { formatEventTime } from "../shell/format";

/**
 * `daily-brief` — the first Report, and the one that proves the format.
 *
 * Split deliberately into **assemble** (providers -> typed snapshot) and **compose** (snapshot ->
 * document), because that seam is the whole point of the archetype: v2 replaces `composeDailyBrief`
 * with a model and keeps `assembleDailyBrief` and the renderer untouched. Everything here is
 * deterministic — same snapshot, same document — so the formula is testable without a clock, a
 * calendar, or a network.
 *
 * News and stocks are deliberately **not** in the formula (owner decision): both remain live
 * providers, so handing them to a future model composer to include when relevant stays cheap.
 */

/** The typed data the composer reads. Nothing in here is presentation. */
export interface DailyBriefSnapshot {
  readonly now: Date;
  readonly weather: {
    readonly state: RegionState;
    readonly temperatureF?: number;
    readonly condition?: string;
  } | null;
  readonly schedule: {
    readonly state: RegionState;
    readonly items: readonly ScheduleItem[];
  };
  /**
   * Unread mail. `null` means *no mail provider exists yet* — the count arrives with Gmail
   * (PRD excludes Workspace from the MVP). A composer must render nothing rather than a zero,
   * because "0 unread" is a claim we cannot make.
   */
  readonly unreadCount: number | null;
}

/** Time-of-day greeting. Deliberately the only thing that reads the clock's hour. */
function greetingFor(now: Date): string {
  const hour = now.getHours();
  if (hour < 12) {
    return "Good morning.";
  }
  return hour < 18 ? "Good afternoon." : "Good evening.";
}

function formatNow(now: Date): string {
  const time = now.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
  const date = now.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" });
  return `It's ${time} on ${date}.`;
}

function weatherBlock(snapshot: DailyBriefSnapshot): ReportBlock | null {
  const weather = snapshot.weather;
  // No channel at all is different from a channel that failed: say nothing when weather was
  // never configured, and say "Unavailable" when it was and could not be read.
  if (!weather) {
    return null;
  }
  if (weather.state === "unavailable") {
    return { blockKind: "metric", label: "Outside", value: "Unavailable", metricTone: "warning" };
  }
  const parts = [
    weather.temperatureF === undefined ? null : `${Math.round(weather.temperatureF)}°F`,
    weather.condition ?? null
  ].filter((part): part is string => part !== null);

  return parts.length > 0
    ? { blockKind: "metric", label: "Outside", value: parts.join(" · "), metricTone: "neutral" }
    : null;
}

function scheduleBlock(snapshot: DailyBriefSnapshot): ReportBlock {
  const { state, items } = snapshot.schedule;

  if (state === "unavailable") {
    // A muted line, not an `empty` block: an empty calendar and an unreadable one are different
    // facts, and rendering the second as the first would be a quiet lie.
    return { blockKind: "line", text: "Your calendar is unavailable.", lineEmphasis: "muted" };
  }
  if (items.length === 0) {
    return { blockKind: "empty", text: "Nothing scheduled today." };
  }
  return {
    blockKind: "list",
    listItems: items.map((item) => ({
      text: item.title,
      meta: formatEventTime(item.start) || undefined
    }))
  };
}

function unreadBlock(snapshot: DailyBriefSnapshot): ReportBlock | null {
  // `null` = no mail provider; `0` = a real, read count of zero, which is worth stating.
  if (snapshot.unreadCount === null) {
    return null;
  }
  return {
    blockKind: "count",
    value: String(snapshot.unreadCount),
    label: snapshot.unreadCount === 1 ? "unread email" : "unread emails",
    reportAction: { action: "email-report" }
  };
}

/** v1: the formula, in code. v2 swaps this for a model and changes nothing else. */
export function composeDailyBrief(snapshot: DailyBriefSnapshot): ReportDocument {
  const blocks: (ReportBlock | null)[] = [
    { blockKind: "greeting", text: greetingFor(snapshot.now), greetingSize: "hero" },
    { blockKind: "line", text: formatNow(snapshot.now), lineEmphasis: "normal" },
    weatherBlock(snapshot),
    scheduleBlock(snapshot),
    unreadBlock(snapshot)
  ];

  return {
    schemaVersion: REPORT_DOCUMENT_SCHEMA_VERSION,
    reportId: "daily-brief",
    blocks: blocks.filter((block): block is ReportBlock => block !== null)
  };
}
