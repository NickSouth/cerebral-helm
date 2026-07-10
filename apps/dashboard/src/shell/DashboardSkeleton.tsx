import { SkeletonBone as Bone } from "../components/Skeleton";

/** One rail column of stacked placeholder panels, mirroring the populated rail rhythm. */
function RailSkeleton({ panels }: { panels: number }) {
  return (
    <div className="skeleton-rail" aria-hidden="true">
      {Array.from({ length: panels }, (_, index) => (
        <div key={index} className="skeleton-panel">
          <Bone className="skeleton-bone--label" />
          <Bone className="skeleton-bone--row" />
          <Bone className="skeleton-bone--row" />
          <Bone className="skeleton-bone--row" />
        </div>
      ))}
    </div>
  );
}

/**
 * First-paint loading state (NIC-64): a three-zone skeleton that mirrors the shell's layout so
 * there is never a blank screen while data resolves. The shimmer is CSS and is stilled under
 * `prefers-reduced-motion`. Announced once as a polite status; the bones themselves are hidden
 * from assistive tech.
 */
export function DashboardSkeleton() {
  return (
    <div className="dashboard-skeleton" role="status" aria-live="polite" aria-busy="true">
      <span className="sr-only">Loading your dashboard…</span>
      <RailSkeleton panels={3} />
      <div className="skeleton-center" aria-hidden="true">
        <Bone className="skeleton-bone--apps" />
        <Bone className="skeleton-bone--field" />
        <Bone className="skeleton-bone--greeting" />
      </div>
      <RailSkeleton panels={3} />
    </div>
  );
}
