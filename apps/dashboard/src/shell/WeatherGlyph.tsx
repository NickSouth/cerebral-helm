import type { ReactNode } from "react";

/**
 * Weather glyph for the bottom bar: maps the mocked `condition` phrase to a filled line icon and a
 * `data-weather` kind. The kind drives a natural, condition-based color (yellow sun, white cloud,
 * blue rain) via CSS — NOT the mode accent. Partly cloudy is two-tone. The exact condition stays in
 * the item's title.
 */
type WeatherKind = "sun" | "cloud" | "partly" | "rain";

const GLYPHS: Readonly<Record<WeatherKind, ReactNode>> = {
  sun: (
    <>
      <circle cx="12" cy="12" r="4.8" fill="currentColor" />
      <path
        d="M12 1.5V4M12 20v2.5M3.9 3.9l1.8 1.8M18.3 18.3l1.8 1.8M1.5 12H4M20 12h2.5M3.9 20.1 5.7 18.3M18.3 5.7 20.1 3.9"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
      />
    </>
  ),
  cloud: <path d="M7 18.5h9.5a3.75 3.75 0 0 0 0-7.5 5.25 5.25 0 0 0-10.1-1.4A3.75 3.75 0 0 0 7 18.5z" fill="currentColor" />,
  partly: (
    <>
      {/* Two-tone: yellow sun behind, white cloud in front (colored per sub-element in CSS). */}
      <circle className="weather-glyph__sunfill" cx="8" cy="8" r="3.6" fill="currentColor" />
      <path
        className="weather-glyph__sunstroke"
        d="M8 1V2.6M1.6 8H3.2M3 3l1.1 1.1M13 3l-1.1 1.1"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.7"
        strokeLinecap="round"
      />
      <path className="weather-glyph__cloudfill" d="M9 19.5h8.2a3.1 3.1 0 0 0 0-6.2 4.4 4.4 0 0 0-8.4-1A3.1 3.1 0 0 0 9 19.5z" fill="currentColor" />
    </>
  ),
  rain: (
    <>
      <path d="M7.3 15.5h8.4a3.4 3.4 0 0 0 0-6.7 4.8 4.8 0 0 0-9.2-1.2A3.3 3.3 0 0 0 7.3 15.5z" fill="currentColor" />
      <path d="M8.6 18l-.9 2.4M12 18l-.9 2.4M15.4 18l-.9 2.4" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
    </>
  )
};

function kindFor(condition: string): WeatherKind {
  const c = condition.toLowerCase();
  if (c.includes("rain") || c.includes("shower") || c.includes("drizzle") || c.includes("storm")) return "rain";
  if (c.includes("partly") || c.includes("mostly sunny")) return "partly";
  if (c.includes("cloud") || c.includes("overcast") || c.includes("fog")) return "cloud";
  // Sunny / Clear and anything else fall back to the sun.
  return "sun";
}

export function WeatherGlyph({ condition }: { condition: string }) {
  return (
    <svg
      className="weather-glyph"
      data-weather={kindFor(condition)}
      viewBox="0 0 24 24"
      width="20"
      height="20"
      fill="none"
      stroke="currentColor"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      {GLYPHS[kindFor(condition)]}
    </svg>
  );
}
