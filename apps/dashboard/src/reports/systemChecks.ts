import type { SystemCheck, SystemChecksPayload } from "../bridge/cerebralBridge";
import type { SystemHealthRegion } from "../bridge/types";
import {
  REPORT_DOCUMENT_SCHEMA_VERSION,
  type ReportBlock,
  type ReportDocument,
  type ReportListItem
} from "./reportDocument";

/**
 * `system-status-checks` — the streaming Report (quick actions phase 5).
 *
 * **What it checks is the whole idea** (owner decision, 2026-08-04): everything that can change
 * *without a code change*, and nothing that cannot. The test suite already proves this codebase is
 * self-consistent — it has to pass for a build to exist — so re-running any of it here would
 * report a guarantee rather than a finding. What no test can tell you is whether the world still
 * matches: a permission revoked in System Settings, a token that expired overnight, an
 * undocumented endpoint whose fields moved, a folder renamed in Finder.
 *
 * The document is recomposed from scratch on every emission, because each event carries the whole
 * set. That is the same reason the composer is pure: given a payload it produces a document, and
 * "which checks are still running" is a property of the payload rather than of this function.
 *
 * **The live metrics ride in the same document** (owner decision, 2026-08-04, replacing the plan's
 * external window). The two halves are deliberately different in kind and the report says so: the
 * metrics header is genuinely live — it re-renders whenever the status publisher ticks, at no cost
 * — while the checklist is a *snapshot* with a refresh, because re-running it means contacting
 * several third parties. Presenting a snapshot as though it were live would be the more convenient
 * lie and the worse one.
 */

/** Section order and headings. Grouped because the groups are fixed in different places. */
const GROUPS: ReadonlyArray<{ readonly id: SystemCheck["group"]; readonly heading: string }> = [
  { id: "permissions", heading: "Permissions & apps" },
  { id: "integrations", heading: "Integrations" },
  { id: "storage", heading: "Storage" }
];

/** The report's own id, matching the quick action. */
export const SYSTEM_CHECKS_REPORT_ID = "system-status-checks";

function heading(text: string): ReportBlock {
  return { blockKind: "line", text, lineEmphasis: "strong" };
}

/**
 * One row. The detail line carries what was *actually* established — "Key is set. Not contacted"
 * rather than a bare "passed" — because the reader's next question is always "checked how?".
 *
 * A failure's remediation is appended to the same line rather than hidden behind a disclosure: a
 * fix you have to click to see is a fix most people never read.
 */
export function checkItem(check: SystemCheck): ReportListItem {
  const detail = check.detail ?? undefined;
  const text =
    check.state === "failed" && check.remediation
      ? `${check.title} — ${detail ?? "Failed."} ${check.remediation}`
      : detail
        ? `${check.title} — ${detail}`
        : check.title;
  return {
    text,
    status: check.state,
    // Only once it has finished: a duration on a pending row would be a number for something that
    // has not happened.
    meta: check.durationMs != null && check.durationMs > 0 ? `${check.durationMs} ms` : undefined
  };
}

/** The one-line verdict. Says what is wrong, or that nothing is, and never rounds up to "healthy". */
export function summaryLine(payload: SystemChecksPayload): ReportBlock {
  const checks = payload.checks;
  const failed = checks.filter((check) => check.state === "failed").length;
  const skipped = checks.filter((check) => check.state === "skipped").length;
  const done = checks.filter((check) => check.state !== "pending" && check.state !== "running").length;

  if (!payload.complete) {
    return {
      blockKind: "count",
      value: `${done}/${checks.length}`,
      label: "checked so far"
    };
  }
  if (failed > 0) {
    return {
      blockKind: "count",
      value: String(failed),
      label: failed === 1 ? "thing needs attention" : "things need attention",
      metricTone: "critical"
    };
  }
  // Skipped is reported alongside, never folded into "all good": a green line that quietly covered
  // six unconfigured integrations would be the exact dishonesty this surface exists to avoid.
  return {
    blockKind: "count",
    value: String(checks.length - skipped),
    label: skipped > 0 ? `checks passed · ${skipped} not set up` : "checks passed",
    metricTone: "positive"
  };
}

/**
 * The live metrics row: CPU, memory, network, battery — whatever the publisher currently has.
 *
 * A channel with no reading is **omitted rather than zeroed**: "0%" is a measurement, and printing
 * one for a channel this Mac cannot report would be a fabricated number in the one report whose
 * entire purpose is telling the truth about the machine.
 */
export function metricsRow(health: SystemHealthRegion | undefined): ReportBlock | null {
  if (!health || health.state === "unavailable") {
    return null;
  }
  const parts: string[] = [];
  if (typeof health.cpuPercent === "number") {
    parts.push(`CPU ${Math.round(health.cpuPercent)}%`);
  }
  if (typeof health.memoryPercent === "number") {
    parts.push(`Memory ${Math.round(health.memoryPercent)}%`);
  }
  if (typeof health.network?.linkMbps === "number") {
    parts.push(`Network ${Math.round(health.network.linkMbps)} Mbps`);
  }
  if (typeof health.battery?.percent === "number") {
    parts.push(`Battery ${Math.round(health.battery.percent)}%${health.battery.charging ? " ⚡" : ""}`);
  }
  if (parts.length === 0) {
    return null;
  }
  return { blockKind: "metric", label: "Right now", value: parts.join("  ·  ") };
}

export function composeSystemChecks(
  payload: SystemChecksPayload | null | undefined,
  health?: SystemHealthRegion
): ReportDocument {
  if (!payload) {
    // Never run in this session. Not the same as "everything is fine", and not the same as a run
    // that found nothing — so it says which.
    return {
      schemaVersion: REPORT_DOCUMENT_SCHEMA_VERSION,
      reportId: SYSTEM_CHECKS_REPORT_ID,
      // The one report the reader can re-run rather than re-read: these answers go stale exactly
      // while you are looking away from them.
      refreshable: true,
      blocks: [metricsRow(health), { blockKind: "empty", text: "Checking…" }].filter(
        (block): block is ReportBlock => block !== null
      )
    };
  }

  // Metrics lead: they are always current, so the top of the report is never stale even while the
  // checklist below it is mid-run.
  const metrics = metricsRow(health);
  const blocks: ReportBlock[] = metrics ? [metrics, summaryLine(payload)] : [summaryLine(payload)];

  for (const group of GROUPS) {
    const rows = payload.checks.filter((check) => check.group === group.id);
    if (rows.length === 0) {
      continue;
    }
    blocks.push(heading(group.heading));
    blocks.push({ blockKind: "checklist", listItems: rows.map(checkItem) });
  }

  if (payload.checks.length === 0) {
    blocks.push({
      blockKind: "empty",
      text: "This host has nothing to check — the checks are macOS-only."
    });
  }

  return {
    schemaVersion: REPORT_DOCUMENT_SCHEMA_VERSION,
    reportId: SYSTEM_CHECKS_REPORT_ID,
    refreshable: true,
    blocks
  };
}
