interface StaleMarkerProps {
  /** Override the default "may be out of date" phrasing for a specific region. */
  label?: string;
}

/**
 * The stale-data marker (NIC-64): a small inline indicator that content is showing but older
 * than its freshness window (e.g. while offline). The status is carried by text, never color
 * alone (constitution §2) — the amber tone is only reinforcement.
 */
export function StaleMarker({ label = "May be out of date" }: StaleMarkerProps) {
  return (
    <span className="stale-marker" data-state="stale" role="note">
      <span className="stale-marker__dot" aria-hidden="true" />
      {label}
    </span>
  );
}

export default StaleMarker;
