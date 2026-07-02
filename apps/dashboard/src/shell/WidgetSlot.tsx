import type { ReactNode } from "react";
import { Panel } from "./Panel";
import { PanelGlyph, type PanelGlyphName } from "./PanelGlyph";
import { StaleMarker } from "../components/StaleMarker";
import { Unavailable } from "../components/Unavailable";
import { EmptyState } from "../components/EmptyState";
import { WIDGET_REGISTRY } from "../widgets/widgets";
import type { WidgetData } from "../widgets/widgetData";
import { formatDay } from "./format";

const WIDGET_LABELS: ReadonlyMap<string, string> = new Map(
  WIDGET_REGISTRY.map((widget) => [widget.id, widget.label])
);

/** Icon-first annotation per widget id (visual reference); unknown ids fall back to a generic glyph. */
const WIDGET_ICONS: Readonly<Record<string, PanelGlyphName>> = {
  "market-brief": "market",
  "project-git-status": "git",
  repositories: "git",
  projects: "projects",
  deadlines: "deadlines",
  spotify: "music",
  courses: "courses",
  "media-list": "media"
};

function row(primary: ReactNode, secondary: ReactNode, key: string | number) {
  return (
    <li key={key} className="widget-list__item">
      <span className="widget-list__primary">{primary}</span>
      <span className="widget-list__secondary">{secondary}</span>
    </li>
  );
}

function list(children: ReactNode) {
  return <ul className="widget-list">{children}</ul>;
}

/**
 * Per-widget body renderers, keyed by widget id — the registry-driven slot (design spec
 * §5.3): a widget id resolves to its own renderer, never a per-mode conditional. Each reads
 * its slice of the WidgetData payload.
 *
 * The payload is intentionally heterogeneous: each renderer knows only its own widget's
 * shape, so `data` is untyped at this dispatch boundary (WidgetBody hands it in as an
 * unknown-derived record). Typed per-widget payloads are deferred to the widget-data
 * contract work; the explicit-any allowance is scoped to this registry only.
 */
/* eslint-disable @typescript-eslint/no-explicit-any */
const WIDGET_BODIES: Readonly<Record<string, (data: any) => ReactNode>> = {
  "market-brief": (data) =>
    list(
      (data.tickers ?? []).map((ticker: any, index: number) =>
        row(ticker.symbol, `${ticker.changePct > 0 ? "+" : ""}${ticker.changePct}%`, index)
      )
    ),
  "project-git-status": (data) =>
    list(
      <>
        {row("Branch", data.branch, "branch")}
        {row("Checks", data.checks, "checks")}
        {typeof data.openPullRequests === "number"
          ? row("Open PRs", data.openPullRequests, "prs")
          : null}
      </>
    ),
  deadlines: (data) =>
    list(
      (data.items ?? []).map((item: any, index: number) =>
        row(item.title, formatDay(item.dueAt), index)
      )
    ),
  spotify: (data) => list(row(data.track, data.artist, "track")),
  projects: (data) =>
    list((data.items ?? []).map((item: any, index: number) => row(item.name, item.status, index))),
  repositories: (data) =>
    list(
      (data.items ?? []).map((item: any, index: number) =>
        row(item.name, `${item.branch} · ${item.state}`, index)
      )
    ),
  courses: (data) =>
    list((data.items ?? []).map((item: any, index: number) => row(item.name, item.next, index))),
  "media-list": (data) =>
    list((data.items ?? []).map((item: any, index: number) => row(item.title, item.kind, index)))
};
/* eslint-enable @typescript-eslint/no-explicit-any */

function WidgetBody({ widgetId, data }: { widgetId: string; data: unknown }) {
  const render = WIDGET_BODIES[widgetId];
  return render ? <>{render((data ?? {}) as Record<string, unknown>)}</> : <Unavailable />;
}

/**
 * A free-widget slot (left or right). Resolves the widget id to its registry label and body
 * renderer; degraded states (empty / stale / unavailable) render honestly with the freshness
 * indicator (design spec §5.3).
 */
export function WidgetSlot({ data, labelId }: { data: WidgetData; labelId: string }) {
  const label = WIDGET_LABELS.get(data.widgetId) ?? data.widgetId;
  const live = data.state === "ready" || data.state === "stale";

  return (
    <Panel
      label={label}
      labelId={labelId}
      icon={<PanelGlyph name={WIDGET_ICONS[data.widgetId] ?? "widget"} />}
    >
      {live ? (
        <div className="widget">
          {data.state === "stale" ? <StaleMarker /> : null}
          {data.headline ? <p className="widget__headline">{data.headline}</p> : null}
          <WidgetBody widgetId={data.widgetId} data={data.data} />
          {data.freshness ? <p className="widget__freshness">{data.freshness.label}</p> : null}
        </div>
      ) : data.state === "empty" ? (
        // Resolved with no data — a healthy zero-result, not a missing capability.
        <EmptyState label={data.emptyMessage ?? "Nothing to show yet"} />
      ) : (
        <Unavailable label={data.emptyMessage ?? "Unavailable"} />
      )}
    </Panel>
  );
}
