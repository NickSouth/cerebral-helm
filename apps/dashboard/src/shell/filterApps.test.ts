import { describe, expect, it } from "vitest";
import { filterApps } from "./filterApps";
import type { DiscoveredApp } from "../bridge/cerebralBridge";

const APPS: readonly DiscoveredApp[] = [
  { bundleId: "com.apple.Safari", name: "Safari" },
  { bundleId: "com.apple.Terminal", name: "Terminal" },
  { bundleId: "com.microsoft.VSCode", name: "Visual Studio Code" },
  { bundleId: "com.valvesoftware.steam", name: "Steam" }
];

const names = (apps: readonly DiscoveredApp[]) => apps.map((app) => app.name);

describe("filterApps", () => {
  it("returns the list unchanged for an empty or whitespace query", () => {
    expect(filterApps(APPS, "")).toBe(APPS);
    expect(filterApps(APPS, "   ")).toBe(APPS);
  });

  it("matches the display name, case-insensitively", () => {
    expect(names(filterApps(APPS, "saf"))).toEqual(["Safari"]);
    expect(names(filterApps(APPS, "SAFARI"))).toEqual(["Safari"]);
    // A substring anywhere in the name, not just a prefix — "code" should find "Visual Studio Code".
    expect(names(filterApps(APPS, "code"))).toEqual(["Visual Studio Code"]);
  });

  it("falls back to the bundle id so a vendor prefix still finds apps", () => {
    expect(names(filterApps(APPS, "com.apple"))).toEqual(["Safari", "Terminal"]);
    expect(names(filterApps(APPS, "valvesoftware"))).toEqual(["Steam"]);
  });

  it("preserves the caller's ordering rather than re-ranking", () => {
    // The list arrives alphabetically sorted from discovery; a filter is not the place to re-rank,
    // so a query matching several apps keeps them in the order the user already sees.
    expect(names(filterApps(APPS, "s"))).toEqual(["Safari", "Visual Studio Code", "Steam"]);
  });

  it("returns nothing for a query that matches nothing — no fuzzy near-misses", () => {
    // A typo must produce an honest empty result, not a confident wrong answer.
    expect(filterApps(APPS, "sfari")).toEqual([]);
    expect(filterApps(APPS, "zzz")).toEqual([]);
  });

  it("trims the query so trailing whitespace does not silently match nothing", () => {
    expect(names(filterApps(APPS, "  steam  "))).toEqual(["Steam"]);
  });
});
