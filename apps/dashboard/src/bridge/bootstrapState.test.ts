import { loadBootstrapState } from "./mockCerebralBridge";
import { getDashboardConfigBundle, dashboardStoryFixtures } from "../fixtures/canonicalFixtures";
import { MODE_IDS } from "../tokens/tokens";
import { isRegisteredWidgetId } from "../widgets/widgets";

describe("expanded bootstrap state", () => {
  it("composes the eager config bundle with the active-mode snapshot", () => {
    const state = loadBootstrapState();

    expect(state.mode).toBe("Executive"); // Executive is the default mode (ADR-007).
    // Eager: all four resolved mode views ship up front (no-flash switching).
    expect(state.modes).toHaveLength(4);
    expect([...state.modes].map((mode) => mode.id).sort()).toEqual([...MODE_IDS].sort());
    // Fixed global roster, identical in every mode.
    expect(state.agents).toHaveLength(4);
    expect(state.agents.every((agent) => agent.activity === "idle")).toBe(true);
  });

  it("boots with Heimlich owning the center and no agent expanded (A.1 / B)", () => {
    const state = loadBootstrapState();

    // Heimlich is always present; the chat overlay is closed by default (never replaces the center).
    expect(state.heimlich.state).toBe("idle");
    expect(state.heimlich.conversation.open).toBe(false);
    // expandedAgent defaults to null in every mode — nothing covers the right column by default.
    expect(state.expandedAgent).toBeNull();
  });

  it("carries active-mode region data with resolvable widget slots", () => {
    const { regions } = loadBootstrapState();

    expect(regions.schedule.state).toBe("ready");
    expect(regions.news.headlines.length).toBeLessThanOrEqual(3);
    // Battery is an honest unavailable capability pre-Mac.
    expect(regions.systemHealth.battery.state).toBe("unavailable");
    expect(isRegisteredWidgetId(regions.widgets.left.widgetId)).toBe(true);
    expect(isRegisteredWidgetId(regions.widgets.right.widgetId)).toBe(true);
  });

  it("keeps every mode view's theme tokens aligned with the registered mode token ids", () => {
    const bundle = getDashboardConfigBundle();

    for (const mode of bundle.modes) {
      expect(mode.theme.accentPrimary).toBe(`${mode.id}.primary`);
      expect(mode.theme.accentSecondary).toBe(`${mode.id}.secondary`);
      expect(mode.quickActions).toHaveLength(8);
    }
  });

  it("ships a region snapshot for every canonical dashboard fixture (no blank regions)", () => {
    for (const fixture of dashboardStoryFixtures) {
      expect(fixture.dashboardState.regions).toBeDefined();
      expect(fixture.dashboardState.regions.widgets.left.widgetId).toBeTruthy();
    }
  });
});
