import type { ReactNode } from "react";

/**
 * System Health category glyphs (design spec §5.2): a small line icon on the left of each
 * metric row (CPU, memory, network, battery). Same construction as {@link AppGlyph}; inherits
 * color from the row via `currentColor`.
 */
export type HealthGlyphName = "cpu" | "memory" | "network" | "network-off" | "battery";

const GLYPHS: Readonly<Record<HealthGlyphName, ReactNode>> = {
  // Processor die with pins.
  cpu: (
    <>
      <rect x="6" y="6" width="12" height="12" rx="1.5" />
      <rect x="9.5" y="9.5" width="5" height="5" rx="0.8" />
      <path d="M9 3v3M15 3v3M9 18v3M15 18v3M3 9h3M3 15h3M18 9h3M18 15h3" />
    </>
  ),
  // RAM module with notches.
  memory: (
    <>
      <rect x="3" y="7" width="18" height="9" rx="1.5" />
      <path d="M7 10v3M12 10v3M17 10v3M6 16v2M10 16v2M14 16v2M18 16v2" />
    </>
  ),
  // Wi-Fi arcs, outermost first. The arcs carry strength classes so a weak signal
  // dims the outer ones (see `signalLevelFromRssi`); with no reading they all render
  // at full strength rather than implying a measurement that was never taken.
  network: (
    <>
      <path className="health-glyph__arc health-glyph__arc--3" d="M2.5 8.5a14 14 0 0 1 19 0" />
      <path className="health-glyph__arc health-glyph__arc--2" d="M5.5 12a9.5 9.5 0 0 1 13 0" />
      <path className="health-glyph__arc health-glyph__arc--1" d="M8.5 15.4a5 5 0 0 1 7 0" />
      <path d="M12 18.8h.01" />
    </>
  ),
  // Wi-Fi arcs struck through: the radio is off, or the machine has none.
  "network-off": (
    <>
      <path d="M2.5 8.5a14 14 0 0 1 19 0" />
      <path d="M5.5 12a9.5 9.5 0 0 1 13 0" />
      <path d="M8.5 15.4a5 5 0 0 1 7 0" />
      <path d="M12 18.8h.01" />
      <path d="M3.5 3.5l17 17" />
    </>
  ),
  // Battery body + terminal.
  battery: (
    <>
      <rect x="3" y="8" width="16" height="8" rx="1.6" />
      <path d="M21.5 11v2" />
    </>
  )
};

/** How many of the Wi-Fi glyph's three arcs render at full strength. */
export type SignalLevel = 1 | 2 | 3;

/**
 * Wi-Fi signal strength in dBm → arc count (NIC-156). RSSI is negative and closer to
 * zero is stronger; the boundaries are the conventional strong/usable/weak split.
 * `undefined` in means `undefined` out — an absent reading dims nothing, because
 * "we did not measure this" is not the same as "the signal is weak".
 */
export function signalLevelFromRssi(rssi: number | undefined): SignalLevel | undefined {
  if (rssi === undefined || !Number.isFinite(rssi)) {
    return undefined;
  }
  if (rssi >= -60) {
    return 3;
  }
  return rssi >= -75 ? 2 : 1;
}

export function HealthGlyph({
  name,
  signalLevel
}: {
  name: HealthGlyphName;
  /** Wi-Fi arcs only: dims the arcs above this level. Omit to render all at full strength. */
  signalLevel?: SignalLevel;
}) {
  return (
    <svg
      className="health-glyph"
      data-signal={name === "network" ? signalLevel : undefined}
      viewBox="0 0 24 24"
      width="16"
      height="16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      {GLYPHS[name]}
    </svg>
  );
}
