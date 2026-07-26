import type { ReactNode } from "react";
import { Panel } from "./Panel";
import { PanelGlyph, type PanelGlyphName } from "./PanelGlyph";
import { StaleMarker } from "../components/StaleMarker";
import { Unavailable } from "../components/Unavailable";
import { EmptyState } from "../components/EmptyState";
import { WIDGET_REGISTRY } from "../widgets/widgets";
import type { ProjectWidgetItem, RepositoryWidgetItem, WidgetData } from "../widgets/widgetData";
import { useBridge } from "../state/BridgeProvider";
import { useActionStatus } from "../state/ActionStatusProvider";
import { useUiPosture } from "../state/useUiPosture";
import { submitOpenProject } from "./openProject";
import { submitOpenProjectDetail } from "./openProjectDetail";
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
  releases: "media"
};

/** Human label for a release's media type (never a fabricated category). */
function releaseKindLabel(mediaType: unknown): string {
  return mediaType === "tv" ? "TV" : "Movie";
}

/** "Movie · 2025" / "TV · 2024" / "Movie" — year is dropped when TMDB has no release date. */
function releaseMeta(item: { mediaType?: unknown; year?: unknown }): string {
  const kind = releaseKindLabel(item.mediaType);
  return typeof item.year === "number" ? `${kind} · ${item.year}` : kind;
}

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
  courses: (data) =>
    list((data.items ?? []).map((item: any, index: number) => row(item.name, item.next, index))),
  releases: (data) => (
    <>
      {list(
        (data.items ?? []).map((item: any, index: number) =>
          row(item.title, releaseMeta(item), item.id ?? index)
        )
      )}
      {/* TMDB terms require attributing the source for any use of their API (NIC-134). */}
      <p className="widget__attribution">
        This product uses the TMDB API but is not endorsed or certified by TMDB.
      </p>
    </>
  )
};
/* eslint-enable @typescript-eslint/no-explicit-any */

/** A small line-icon folder mark for a repo row (matches the PanelGlyph line-icon convention). */
function FolderGlyph() {
  return (
    <svg
      className="repo-row__icon"
      viewBox="0 0 24 24"
      width="15"
      height="15"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M4 7.5A1.5 1.5 0 0 1 5.5 6h3l2 2h8A1.5 1.5 0 0 1 20 9.5v7a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 16.5z" />
    </svg>
  );
}

/**
 * The Developer "Repositories" widget body (NIC-131): each active repo is a clickable row
 * showing its name and current branch. Clicking opens the repo in the configured editor
 * through the gated `project.open` path (`submitOpenProject`); read-only recovery disables
 * the rows, and a rejected dispatch is surfaced honestly in the status line — never a
 * fabricated success. Unlike the static renderers, this needs the bridge/posture/status
 * hooks, so it is a component rather than a pure `(data) => ReactNode` entry.
 */
function RepositoriesBody({ items }: { items: readonly RepositoryWidgetItem[] }) {
  const bridge = useBridge();
  const { announce } = useActionStatus();
  const { readOnly } = useUiPosture();

  const open = (item: RepositoryWidgetItem) => {
    void submitOpenProject(bridge, item.path)
      .then((receipt) => {
        if (!receipt.accepted) {
          announce(`I couldn't open ${item.name} — the command wasn't accepted.`, "error");
        }
      })
      .catch(() => {
        announce(`Opening ${item.name} failed — the bridge did not accept it.`, "error");
      });
  };

  return (
    <ul className="widget-list">
      {items.map((item) => (
        <li key={item.id} className="widget-list__item">
          <button
            type="button"
            className="widget-list__button"
            disabled={readOnly}
            aria-disabled={readOnly || undefined}
            title={
              readOnly
                ? "Opening a repository is paused while the dashboard is read-only"
                : `Open ${item.name} in the editor`
            }
            onClick={() => {
              open(item);
            }}
          >
            <span className="repo-row__name">
              <FolderGlyph />
              <span className="repo-row__label">{item.name}</span>
            </span>
            {item.branch ? (
              <code className="repo-row__branch">{item.branch}</code>
            ) : (
              <span className="repo-row__branch repo-row__branch--none" aria-label="no branch">
                —
              </span>
            )}
          </button>
        </li>
      ))}
    </ul>
  );
}

/**
 * The Executive "Projects" widget body (NIC-129): each project is a clickable row that opens
 * its `PROJECT.md` in a native detail window (`shellControl.openProjectDetail`, owned by the
 * `WindowCoordinator`). A project with no descriptor is honestly non-expandable — the row is
 * disabled rather than opening an empty window — and read-only recovery disables every row.
 * Like `RepositoriesBody`, this needs the posture hook, so it is a component rather than a
 * static `WIDGET_BODIES` entry.
 */
function ProjectsBody({ items }: { items: readonly ProjectWidgetItem[] }) {
  const { readOnly } = useUiPosture();

  return (
    <ul className="widget-list">
      {items.map((item) => {
        const expandable = item.hasDescriptor && !readOnly;
        return (
          <li key={item.id} className="widget-list__item">
            <button
              type="button"
              className="widget-list__button"
              disabled={!expandable}
              aria-disabled={!expandable || undefined}
              title={
                readOnly
                  ? "Opening a project is paused while the dashboard is read-only"
                  : item.hasDescriptor
                    ? `Open ${item.name}`
                    : `${item.name} has no PROJECT.md yet`
              }
              onClick={() => {
                submitOpenProjectDetail(item.path);
              }}
            >
              <span className="repo-row__name">
                <FolderGlyph />
                <span className="repo-row__label">{item.name}</span>
              </span>
            </button>
          </li>
        );
      })}
    </ul>
  );
}

function WidgetBody({ widgetId, data }: { widgetId: string; data: unknown }) {
  // The repositories widget renders interactive rows (click-to-open), so it needs runtime
  // hooks and is dispatched to its own component instead of a pure static renderer (NIC-131).
  if (widgetId === "repositories") {
    const items = (data as { items?: readonly RepositoryWidgetItem[] })?.items ?? [];
    return <RepositoriesBody items={items} />;
  }
  // The projects widget likewise renders interactive rows (click-to-expand a detail window).
  if (widgetId === "projects") {
    const items = (data as { items?: readonly ProjectWidgetItem[] })?.items ?? [];
    return <ProjectsBody items={items} />;
  }
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
