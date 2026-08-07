import { SkeletonBone as Bone } from "../components/Skeleton";

/**
 * The body shapes a widget can load into. A skeleton earns its keep only by predicting the
 * layout that replaces it — bones in the wrong shape make the panel jump when data lands, which
 * reads worse than the honest empty state it replaced (NIC-136's same-shape rule).
 */
type WidgetSkeletonShape = "rows" | "tiles" | "posters" | "media" | "report";

/**
 * Per-widget body shape, mirroring how `WIDGET_ICONS` annotates each widget id. A widget absent
 * from this map falls back to `rows`, which is the shape most widget bodies actually use
 * (repositories, projects, deadlines, courses are all `.widget-list`-style row lists), so a new
 * widget gets a sensible loader for free and only needs a line here if it is shaped differently.
 */
const WIDGET_SKELETON_SHAPES: Readonly<Record<string, WidgetSkeletonShape>> = {
  stocks: "tiles",
  releases: "posters",
  spotify: "media",
  "project-git-status": "report"
};

/** Row list — a wide primary label with a short trailing value, the `.widget-list__item` rhythm. */
function RowsSkeleton() {
  return (
    <div className="widget-skeleton__rows">
      {Array.from({ length: 4 }, (_, index) => (
        <div key={index} className="widget-skeleton__row">
          <Bone className="widget-skeleton__row-primary" />
          <Bone className="widget-skeleton__row-secondary" />
        </div>
      ))}
    </div>
  );
}

/** The stocks 2×2 tile grid: symbol, price, and change stacked inside each tile. */
function TilesSkeleton() {
  return (
    <div className="widget-skeleton__tiles">
      {Array.from({ length: 4 }, (_, index) => (
        <div key={index} className="widget-skeleton__tile">
          <Bone className="widget-skeleton__tile-symbol" />
          <Bone className="widget-skeleton__tile-price" />
          <Bone className="widget-skeleton__tile-change" />
        </div>
      ))}
    </div>
  );
}

/** The releases pair: two full-size posters, each with a title and a meta line beneath. */
function PostersSkeleton() {
  return (
    <div className="widget-skeleton__posters">
      {Array.from({ length: 2 }, (_, index) => (
        <div key={index} className="widget-skeleton__poster-cell">
          <Bone className="widget-skeleton__poster" />
          <Bone className="widget-skeleton__poster-title" />
          <Bone className="widget-skeleton__poster-meta" />
        </div>
      ))}
    </div>
  );
}

/**
 * The now-playing card: square artwork beside stacked track/artist/album lines, then the
 * progress bar. Deliberately the same arrangement `SpotifyBody` already uses for its optimistic
 * skip skeleton (NIC-133), so the two loading moments look like one idea.
 */
function MediaSkeleton() {
  return (
    <div className="widget-skeleton__media">
      <div className="widget-skeleton__media-main">
        <Bone className="widget-skeleton__art" />
        <div className="widget-skeleton__media-meta">
          <Bone className="widget-skeleton__media-track" />
          <Bone className="widget-skeleton__media-artist" />
          <Bone className="widget-skeleton__media-album" />
        </div>
      </div>
      <Bone className="widget-skeleton__media-bar" />
    </div>
  );
}

/** The per-repo git report: a name/branch head, a sync line, then label/value rows. */
function ReportSkeleton() {
  return (
    <div className="widget-skeleton__report">
      <div className="widget-skeleton__report-head">
        <Bone className="widget-skeleton__report-name" />
        <Bone className="widget-skeleton__report-branch" />
      </div>
      <Bone className="widget-skeleton__report-sync" />
      {Array.from({ length: 3 }, (_, index) => (
        <div key={index} className="widget-skeleton__report-line">
          <Bone className="widget-skeleton__report-label" />
          <Bone className="widget-skeleton__report-value" />
        </div>
      ))}
    </div>
  );
}

const SHAPE_BODIES: Readonly<Record<WidgetSkeletonShape, () => React.JSX.Element>> = {
  rows: RowsSkeleton,
  tiles: TilesSkeleton,
  posters: PostersSkeleton,
  media: MediaSkeleton,
  report: ReportSkeleton
};

/**
 * A widget's loading body (NIC-174): shown while a slot is still waiting on the first word from
 * its producer, in place of the bootstrap stub's "Unavailable".
 *
 * Announced once as a polite status — a sighted user reads the shimmer, and this is the
 * equivalent cue for anyone who cannot. The bones themselves are decorative and hidden, matching
 * `DashboardSkeleton`. The shimmer is CSS and is stilled by the global reduced-motion safety net,
 * so the shape still communicates "loading" without movement.
 */
export function WidgetSkeleton({ widgetId, label }: { widgetId: string; label: string }) {
  const Body = SHAPE_BODIES[WIDGET_SKELETON_SHAPES[widgetId] ?? "rows"];
  return (
    <div className="widget-skeleton" role="status" aria-live="polite" aria-busy="true">
      <span className="sr-only">Loading {label}…</span>
      <div aria-hidden="true">
        <Body />
      </div>
    </div>
  );
}

export default WidgetSkeleton;
