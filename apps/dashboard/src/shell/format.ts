const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"] as const;

/** `HH:MM` (UTC) from an ISO instant — deterministic for snapshots (no local timezone). */
export function formatClock(iso?: string): string {
  return iso && iso.length >= 16 ? iso.slice(11, 16) : "";
}

/** `Jun 30` (UTC) from an ISO date/instant — deterministic. */
export function formatDay(iso?: string): string {
  if (!iso || iso.length < 10) {
    return "";
  }
  const [, month, day] = iso.slice(0, 10).split("-");
  return `${MONTHS[Number(month) - 1] ?? month} ${Number(day)}`;
}
