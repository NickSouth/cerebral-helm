import { describe, it, expect } from "vitest";
import { resolveWidgetData, type WidgetData } from "./widgetData";

const bootstrap: WidgetData = { widgetId: "repositories", state: "unavailable", emptyMessage: "Unavailable" };
const live: WidgetData = { widgetId: "repositories", state: "ready", data: { items: [] } };

describe("resolveWidgetData (NIC-131 blueprint)", () => {
  it("returns the bootstrap value when no live producer has streamed for the id", () => {
    expect(resolveWidgetData(undefined, "repositories", bootstrap)).toBe(bootstrap);
    expect(resolveWidgetData({}, "repositories", bootstrap)).toBe(bootstrap);
    expect(resolveWidgetData({ projects: live }, "repositories", bootstrap)).toBe(bootstrap);
  });

  it("prefers the live value once its producer has streamed for the id", () => {
    expect(resolveWidgetData({ repositories: live }, "repositories", bootstrap)).toBe(live);
  });
});
