/**
 * Battery glyph for the bottom bar: an outline that fills proportionally to the charge level, tinted
 * by the same thresholds as the System Health bar (green > 60, yellow ≥ 20, red < 20). The fill
 * width is the non-color cue; a title/label carries the exact percentage.
 */
function batteryTone(percent: number): string {
  if (percent > 60) return "good";
  if (percent >= 20) return "warning";
  return "danger";
}

export function BatteryGlyph({ percent }: { percent: number }) {
  const clamped = Math.max(0, Math.min(100, percent));
  const tone = batteryTone(clamped);
  // Interior track runs x 3.5 → 17.5 (width 14); the fill scales with charge.
  const fillWidth = (14 * clamped) / 100;
  return (
    <svg
      className="battery-glyph"
      data-tone={tone}
      viewBox="0 7 24 10"
      width="24"
      height="10"
      fill="none"
      aria-hidden="true"
      focusable="false"
    >
      <rect x="2" y="8" width="17" height="8" rx="2" stroke="currentColor" strokeWidth="1.4" />
      <rect x="20" y="10.5" width="1.8" height="3" rx="0.6" fill="currentColor" />
      <rect className="battery-glyph__fill" data-tone={tone} x="3.5" y="9.5" width={fillWidth} height="5" rx="1" />
    </svg>
  );
}
