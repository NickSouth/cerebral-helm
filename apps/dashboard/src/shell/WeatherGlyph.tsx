import type { ReactNode } from "react";

/**
 * Weather glyph for the bottom bar: maps the `condition` phrase to a filled icon and a
 * `data-weather` kind. The kind drives a natural, condition-based color (yellow sun, white cloud,
 * blue rain, icy snow, grey fog, stormy thunder) via CSS — NOT the mode accent. Partly cloudy and
 * thunder are two-tone. The exact condition phrase stays in the item's title.
 */
type WeatherKind = "sun" | "cloud" | "partly" | "rain" | "snow" | "fog" | "thunder";

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
  cloud: (
    <path
      d="M7 18.5h9.5a3.75 3.75 0 0 0 0-7.5 5.25 5.25 0 0 0-10.1-1.4A3.75 3.75 0 0 0 7 18.5z"
      fill="currentColor"
    />
  ),
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
      <path
        className="weather-glyph__cloudfill"
        d="M9 19.5h8.2a3.1 3.1 0 0 0 0-6.2 4.4 4.4 0 0 0-8.4-1A3.1 3.1 0 0 0 9 19.5z"
        fill="currentColor"
      />
    </>
  ),
  rain: (
    <>
      <path
        d="M7.3 15.5h8.4a3.4 3.4 0 0 0 0-6.7 4.8 4.8 0 0 0-9.2-1.2A3.3 3.3 0 0 0 7.3 15.5z"
        fill="currentColor"
      />
      <path
        d="M8.6 18l-.9 2.4M12 18l-.9 2.4M15.4 18l-.9 2.4"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.7"
        strokeLinecap="round"
      />
    </>
  ),
  snow: (
    <>
      {/* Filled cloud with three snow-flake discs falling below. */}
      <path
        d="M7.3 15.5h8.4a3.4 3.4 0 0 0 0-6.7 4.8 4.8 0 0 0-9.2-1.2A3.3 3.3 0 0 0 7.3 15.5z"
        fill="currentColor"
      />
      <circle cx="8.6" cy="19" r="1.05" fill="currentColor" />
      <circle cx="12" cy="20.5" r="1.05" fill="currentColor" />
      <circle cx="15.4" cy="19" r="1.05" fill="currentColor" />
    </>
  ),
  fog: (
    <>
      {/* Filled cloud over two rounded mist bars. */}
      <path
        d="M7.3 14h8.4a3.4 3.4 0 0 0 0-6.7 4.8 4.8 0 0 0-9.2-1.2A3.3 3.3 0 0 0 7.3 14z"
        fill="currentColor"
      />
      <rect x="5.5" y="17.2" width="11" height="1.8" rx="0.9" fill="currentColor" />
      <rect x="7.5" y="20.3" width="8" height="1.8" rx="0.9" fill="currentColor" />
    </>
  ),
  thunder: (
    <>
      {/* Two-tone: stormy cloud behind, warm bolt in front (colored per sub-element in CSS). */}
      <path
        className="weather-glyph__thundercloud"
        d="M7.3 13.5h8.4a3.4 3.4 0 0 0 0-6.7 4.8 4.8 0 0 0-9.2-1.2A3.3 3.3 0 0 0 7.3 13.5z"
        fill="currentColor"
      />
      <path
        className="weather-glyph__thunderbolt"
        d="M12.5 13.2l-3.5 5.4h2.6l-1.1 4.2 4.5-6.2h-2.7z"
        fill="currentColor"
      />
    </>
  )
};

function kindFor(condition: string): WeatherKind {
  const c = condition.toLowerCase();
  // Order matters: thunder and snow are checked before rain because "Thunderstorm" and
  // "Snow Showers" also match the rain keywords ("storm" / "shower").
  if (c.includes("thunder") || c.includes("storm")) return "thunder";
  if (c.includes("snow") || c.includes("sleet") || c.includes("blizzard")) return "snow";
  if (c.includes("rain") || c.includes("shower") || c.includes("drizzle")) return "rain";
  if (c.includes("partly") || c.includes("mostly sunny")) return "partly";
  if (c.includes("fog") || c.includes("mist") || c.includes("haze")) return "fog";
  if (c.includes("cloud") || c.includes("overcast")) return "cloud";
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
