interface EmptyStateProps {
  /** The calm, specific "nothing here right now" message. Distinct from unavailable/disabled. */
  label?: string;
}

/**
 * The empty-state primitive (NIC-64): a region that resolved successfully but currently holds
 * no items. Semantically distinct from {@link Unavailable} — this is a healthy zero-result, not
 * a disabled or missing capability, so it reads as calm/informational rather than dashed-off.
 * Carries accessible text, never color alone (constitution §2).
 */
export function EmptyState({ label = "Nothing here right now" }: EmptyStateProps) {
  return (
    <span className="empty-state" data-state="empty">
      {label}
    </span>
  );
}

export default EmptyState;
