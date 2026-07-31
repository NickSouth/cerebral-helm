const MONTHS = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec"
] as const;

/** `HH:MM` (UTC) from an ISO instant — deterministic for snapshots (no local timezone). */
export function formatClock(iso?: string): string {
  return iso && iso.length >= 16 ? iso.slice(11, 16) : "";
}

/** `11:00 PM` from an ISO instant whose `HH:MM` slice is the event's local wall-clock time
 *  (NIC-126) — 12-hour with an AM/PM suffix, no leading zero on the hour. Midnight → `12:00 AM`,
 *  noon → `12:00 PM`. Returns "" when the string has no usable time. */
export function formatEventTime(iso?: string): string {
  if (!iso || iso.length < 16) {
    return "";
  }
  const hours = Number(iso.slice(11, 13));
  const minutes = iso.slice(14, 16);
  if (Number.isNaN(hours)) {
    return "";
  }
  const period = hours < 12 ? "AM" : "PM";
  const hour12 = hours % 12 === 0 ? 12 : hours % 12;
  return `${hour12}:${minutes} ${period}`;
}

/** `Jun 30` (UTC) from an ISO date/instant — deterministic. */
export function formatDay(iso?: string): string {
  if (!iso || iso.length < 10) {
    return "";
  }
  const [, month, day] = iso.slice(0, 10).split("-");
  return `${MONTHS[Number(month) - 1] ?? month} ${Number(day)}`;
}
