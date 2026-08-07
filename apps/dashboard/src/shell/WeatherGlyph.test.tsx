import { render } from "@testing-library/react";
import { WeatherGlyph } from "./WeatherGlyph";

/** The rendered `data-weather` kind for a condition phrase (drives the icon + color). */
function kind(condition: string): string | null {
  const { container } = render(<WeatherGlyph condition={condition} />);
  return container.querySelector(".weather-glyph")?.getAttribute("data-weather") ?? null;
}

describe("WeatherGlyph kindFor routing", () => {
  it("maps the OpenMeteo condition phrases to distinct kinds", () => {
    expect(kind("Clear")).toBe("sun");
    expect(kind("Mainly Clear")).toBe("sun");
    expect(kind("Partly Cloudy")).toBe("partly");
    expect(kind("Overcast")).toBe("cloud");
    expect(kind("Fog")).toBe("fog");
    expect(kind("Drizzle")).toBe("rain");
    expect(kind("Freezing Rain")).toBe("rain");
    expect(kind("Rain Showers")).toBe("rain");
    expect(kind("Snow")).toBe("snow");
    expect(kind("Thunderstorm")).toBe("thunder");
  });

  it("prioritizes snow and thunder over the rain keywords they also contain", () => {
    // "Snow Showers" contains "shower" and "Thunderstorm" contains "storm"; the more
    // specific kind must win so snow doesn't render as rain nor thunder as plain rain.
    expect(kind("Snow Showers")).toBe("snow");
    expect(kind("Thunderstorm")).toBe("thunder");
  });
});
