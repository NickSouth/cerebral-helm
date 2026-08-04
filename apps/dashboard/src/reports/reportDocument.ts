/**
 * The report document the renderer consumes — a hand-written mirror of
 * `packages/contracts/schemas/reports/report-document.schema.json`, following the same pattern as
 * `bridge/types.ts` and `widgets/widgetData.ts`.
 *
 * Mirrored rather than imported from the generated TypeScript because quicktype names types from
 * property paths, so the generated shapes arrive as `Block` / `ListItem` / `PurpleReportAction`.
 * Those names are wrong to spread through the UI, and the generated action type is triplicated
 * (one per usage site). The schema stays authoritative; this is the readable local face of it.
 *
 * The pipeline is `providers -> assemble -> Snapshot -> compose -> ReportDocument -> render`.
 * Only the composer changes when a model replaces the deterministic formula; the renderer never
 * does.
 */

export type ReportBlockKind =
  | "greeting"
  | "line"
  | "metric"
  | "list"
  | "checklist"
  | "empty"
  | "count"
  | "proposal";

/**
 * A clickable destination inside a report — **never a URL**. It names a registered quick action,
 * resolved through the dispatch registry, because once a model composes the document every
 * clickable thing in it is a model-chosen destination.
 */
export interface ReportActionReference {
  readonly action: string;
  readonly params?: Readonly<Record<string, unknown>>;
}

export interface ReportListItem {
  readonly text: string;
  readonly meta?: string;
  /** Leading-dot colour when the item belongs to a coloured grouping (a calendar, a course). */
  readonly color?: string;
  /** Only meaningful on a `checklist` — the streaming variant of a list. */
  readonly status?: "pending" | "running" | "passed" | "failed";
  readonly reportAction?: ReportActionReference;
}

export interface ReportBlock {
  readonly blockKind: ReportBlockKind;
  readonly text?: string;
  readonly label?: string;
  readonly value?: string;
  readonly greetingSize?: "hero" | "standard";
  /** `strong` uses weight, never colour — inside a report, colour means actionable. */
  readonly lineEmphasis?: "normal" | "strong" | "muted";
  readonly metricTone?: "neutral" | "positive" | "warning" | "critical";
  readonly listItems?: readonly ReportListItem[];
  readonly reportAction?: ReportActionReference;
  readonly reportActions?: readonly ReportActionReference[];
}

export interface ReportDocument {
  readonly schemaVersion: string;
  readonly reportId: string;
  readonly blocks: readonly ReportBlock[];
}

export const REPORT_DOCUMENT_SCHEMA_VERSION = "1.0.0";

/**
 * Whether a block carries the fields its own kind needs to render.
 *
 * This exists because the composer will eventually be a model. A block that names a kind but
 * omits its content is a composition bug, not a crash: the renderer drops it and renders the rest,
 * so a half-formed report degrades to a shorter report rather than a blank region.
 */
export function isRenderable(block: ReportBlock): boolean {
  switch (block.blockKind) {
    case "greeting":
    case "line":
    case "empty":
      return hasText(block.text);
    case "proposal":
      return hasText(block.text) || (block.reportActions?.length ?? 0) > 0;
    case "metric":
      return hasText(block.label) && hasText(block.value);
    case "count":
      return hasText(block.value) && hasText(block.label);
    case "list":
    case "checklist":
      return (block.listItems?.length ?? 0) > 0;
    default:
      // An unknown kind from a future composer: skip it rather than guessing.
      return false;
  }
}

function hasText(value?: string): boolean {
  return typeof value === "string" && value.trim().length > 0;
}

/** Drops every block the renderer cannot honestly draw, preserving order. */
export function renderableBlocks(document: ReportDocument): readonly ReportBlock[] {
  return document.blocks.filter(isRenderable);
}
