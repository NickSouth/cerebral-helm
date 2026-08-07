import { WIDGET_IDS, WIDGET_REGISTRY, isRegisteredWidgetId, type WidgetId } from "./widgets";
import manifest from "./widgets.manifest.json";
import fixtures from "./fixtures/widgetData.fixtures.json";

const VALID_SIDES = new Set(["left", "right"]);
const VALID_STATES = new Set(["ready", "empty", "stale", "unavailable"]);

describe("widget registry", () => {
  it("registers exactly the eight design-spec widget slots", () => {
    expect(WIDGET_IDS).toHaveLength(8);
    expect(new Set(WIDGET_IDS).size).toBe(8);
  });

  it("keeps widgets.manifest.json in lockstep with WIDGET_IDS (the gate reads the manifest)", () => {
    expect(manifest.widgetIds).toEqual([...WIDGET_IDS]);
  });

  it("describes every widget with a label, summary, and valid rail sides", () => {
    for (const widget of WIDGET_REGISTRY) {
      expect(widget.label.length).toBeGreaterThan(0);
      expect(widget.summary.length).toBeGreaterThan(0);
      expect(widget.sides.length).toBeGreaterThan(0);
      for (const side of widget.sides) {
        expect(VALID_SIDES.has(side)).toBe(true);
      }
    }
  });

  it("recognizes registered ids and rejects unknown ones", () => {
    expect(isRegisteredWidgetId("stocks")).toBe(true);
    expect(isRegisteredWidgetId("leaderboard")).toBe(false);
  });
});

describe("widget-data fixtures", () => {
  it("provides a ready fixture for every registered widget, keyed by its id", () => {
    const ready = fixtures.ready as Record<string, { widgetId: string; state: string }>;
    expect(Object.keys(ready).sort()).toEqual([...WIDGET_IDS].sort());

    for (const id of WIDGET_IDS) {
      const fixture = ready[id];
      expect(fixture.widgetId).toBe(id);
      expect(fixture.state).toBe("ready");
    }
  });

  it("only references registered widgets and valid states across degraded exemplars", () => {
    const degraded = fixtures.degraded as Record<string, { widgetId: string; state: string }>;
    for (const fixture of Object.values(degraded)) {
      expect(isRegisteredWidgetId(fixture.widgetId)).toBe(true);
      expect(VALID_STATES.has(fixture.state)).toBe(true);
    }
  });
});

// Type-level guard: the registry id union is what consumers bind to.
const _exampleId: WidgetId = "courses";
void _exampleId;
