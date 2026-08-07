/**
 * The shared shimmer primitive. A single placeholder "bone" that stands in for a piece of
 * real content while its data loads, so a widget can render its true shape immediately
 * instead of flashing an empty / unavailable state before the first value arrives (NIC-136).
 * Purely decorative — hidden from assistive tech; the loading intent is announced by the
 * surrounding region. The shimmer is CSS and is stilled under `prefers-reduced-motion`.
 */
export function SkeletonBone({ className }: { className?: string }) {
  return <span className={`skeleton-bone${className ? ` ${className}` : ""}`} aria-hidden="true" />;
}

export default SkeletonBone;
