import {
  REPORT_DOCUMENT_SCHEMA_VERSION,
  type ReportBlock,
  type ReportDocument
} from "./reportDocument";
import type { RegionState, ScheduleItem } from "../bridge/types";
import { type UnreadFacts, unreadLabel, unreadValue } from "./unreadCount";
import { formatEventTime } from "../shell/format";

/**
 * `daily-brief` — the first Report, and the one the model now composes (NIC-228).
 *
 * **The document is now two halves.** The HEADER — greeting, date, weather — stays deterministic
 * and stays here, because it is the part with no judgement in it and because it must render the
 * instant the report opens: a model takes around nine seconds, and a reader should not wait that
 * long to be told what time it is. The BODY is composed by the model from a snapshot assembled
 * host-side, and everything below the header is its work.
 *
 * The old formula did not disappear; it **shrank**. `deterministicBody` is what it used to emit
 * below the header, and it is now the last-resort path: when no model is configured, the runtime is
 * down, or a composition fails twice, the brief is still a brief. That is the only way the formula
 * is reachable — it is not a setting, and a working model always composes.
 *
 * News and stocks are deliberately **not** in the deterministic formula (owner decision). The model
 * gets a far richer snapshot than this file ever assembled — mail previews, the sprint's pace, the
 * profile — because the host assembles for it rather than the web layer.
 */

/** The typed data the composer reads. Nothing in here is presentation. */
export interface DailyBriefSnapshot {
  readonly now: Date;
  readonly weather: {
    readonly state: RegionState;
    readonly temperatureF?: number;
    readonly condition?: string;
    /** Today's forecast high, when the provider supplied one (NIC-228). */
    readonly highF?: number;
  } | null;
  readonly schedule: {
    readonly state: RegionState;
    readonly items: readonly ScheduleItem[];
  };
  /**
   * Unread mail, as measured. `null` means *nothing measured it* — no account connected, or the
   * channel could not read. A composer must render nothing rather than a zero, because "0 unread"
   * is a claim we cannot make.
   */
  readonly unreadCount: UnreadFacts | null;
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
    weather.condition ?? null,
    // The forecast high (NIC-228). At 07:00 the current temperature is the least useful number
    // weather has to offer: "63°F" says nothing about whether the afternoon is worth protecting,
    // and "high 78" says all of it. Appended rather than substituted, because the current reading
    // is still what you feel when you step outside.
    weather.highF === undefined ? null : `high ${Math.round(weather.highF)}°`
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
    value: unreadValue(snapshot.unreadCount),
    // No `listed` — the brief shows no rows, so it answers "how many" and nothing else.
    label: unreadLabel(snapshot.unreadCount),
    // Opens the inbox itself (owner decision, 2026-08-04) rather than the in-app report: the
    // count raises the question "what is it?", and the answer lives in Gmail. `email-report` is
    // one press away on its own slot for the in-app view.
    reportAction: { action: "open-mail" }
  };
}

/**
 * The deterministic header: who is reading, when, and what it is like outside.
 *
 * Rendered immediately on open and never rewritten. It is also the reason a composition failing is
 * survivable — whatever happens below, the brief still opens with something true.
 */
export function headerBlocks(snapshot: DailyBriefSnapshot): ReportBlock[] {
  return [
    { blockKind: "greeting", text: greetingFor(snapshot.now), greetingSize: "hero" },
    { blockKind: "line", text: formatNow(snapshot.now), lineEmphasis: "normal" },
    weatherBlock(snapshot)
  ].filter((block): block is ReportBlock => block !== null);
}

/**
 * What the brief says below the header when no model composed it.
 *
 * The old v1 formula, unchanged in substance: the schedule and the unread count, stated plainly.
 * Reachable only when a composition could not be produced — this is a degradation path, not a mode.
 */
export function deterministicBody(snapshot: DailyBriefSnapshot): ReportBlock[] {
  return [scheduleBlock(snapshot), unreadBlock(snapshot)]
    .filter((block): block is ReportBlock => block !== null);
}

/**
 * Wraps blocks in the envelope. The model never writes one; neither does the fallback.
 *
 * `refreshable` is true exactly when a composition was attempted. The rule for that control is that
 * a report offers it only when it was composed from a fetch the reader can repeat — which a
 * composition is, and which the old ambient-state formula was not. It also matters more here than
 * anywhere: the commonest reason a brief comes back unavailable is a daemon that was still starting,
 * and re-running is the whole remedy.
 */
export function dailyBriefDocument(
  blocks: readonly ReportBlock[],
  refreshable = false
): ReportDocument {
  return {
    schemaVersion: REPORT_DOCUMENT_SCHEMA_VERSION,
    reportId: "daily-brief",
    blocks: [...blocks],
    refreshable
  };
}

/**
 * The whole brief: the deterministic header, then whatever the model wrote.
 *
 * `composed` is the model's document when there is one. While a composition is in flight the body
 * is a single muted line — nine seconds of nothing at all reads as a broken report, and the header
 * alone gives no sign that more is coming.
 */
export function composeDailyBrief(
  snapshot: DailyBriefSnapshot,
  composed: { status: string; document: ReportDocument | null; reason: string | null } | null = null
): ReportDocument {
  const header = headerBlocks(snapshot);

  if (composed === null) {
    // No composition was attempted, so there is nothing to re-run.
    return dailyBriefDocument([...header, ...deterministicBody(snapshot)]);
  }
  if (composed.status === "composing" || composed.status === "idle") {
    return dailyBriefDocument([
      ...header,
      { blockKind: "line", text: "Writing your brief…", lineEmphasis: "muted" }
    ], true);
  }
  if (composed.status === "ready" && composed.document) {
    return dailyBriefDocument([...header, ...composed.document.blocks], true);
  }
  // Unavailable: say why, then fall back to the facts the web layer can state on its own. A reason
  // without a brief would be a worse report than the one this app shipped with.
  return dailyBriefDocument([
    ...header,
    ...(composed.reason
      ? [{ blockKind: "line", text: composed.reason, lineEmphasis: "muted" } as ReportBlock]
      : []),
    ...deterministicBody(snapshot)
  ], true);
}
