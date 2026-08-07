import { describe, it, expect } from "vitest";
import { isWidgetPending, resolveWidgetData, type WidgetData } from "./widgetData";
import { WIDGET_IDS } from "./widgets";

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

/**
 * NIC-174. The whole value of this predicate is the line it draws between two states the contract
 * spells identically — both arrive as `state: "unavailable"`. Getting that line wrong is not a
 * cosmetic bug in either direction: too eager and a real "Unavailable" is hidden behind a skeleton
 * that never resolves; too shy and a freshly-entered mode reads as broken for the beat before its
 * producer streams. The `widgetId` is the only thing that separates them, so these cases pin it.
 */
describe("isWidgetPending (NIC-174)", () => {
  /**
   * What `BootstrapComposer.unavailableWidget()` emits before any producer has spoken.
   *
   * The cast is the point, not a shortcut: `"left"` is a rail *side*, not a member of
   * `WIDGET_REGISTRY`, so no real widget can ever collide with it. That is precisely what makes
   * the id usable as a sentinel — and why nothing else in the tree may adopt these two ids.
   */
  const stub = {
    widgetId: "left",
    state: "unavailable",
    emptyMessage: "Unavailable"
  } as unknown as WidgetData;
  /** What a producer emits when it has looked and there is genuinely nothing to show. */
  const declared: WidgetData = {
    widgetId: "stocks",
    state: "unavailable",
    emptyMessage: "Add symbols in Settings"
  };
  const ready: WidgetData = { widgetId: "stocks", state: "ready", data: { items: [] } };

  it("is pending while the slot holds the bootstrap stub and nothing has streamed", () => {
    expect(isWidgetPending(undefined, "stocks", stub)).toBe(true);
    expect(isWidgetPending({}, "stocks", stub)).toBe(true);
    // Another widget streaming says nothing about this slot.
    expect(isWidgetPending({ deadlines: ready }, "stocks", stub)).toBe(true);
  });

  it("is not pending once this slot's producer has streamed", () => {
    expect(isWidgetPending({ stocks: ready }, "stocks", stub)).toBe(false);
    // Including when what it streamed is itself unavailable — that is an answer, not a silence.
    expect(isWidgetPending({ stocks: declared }, "stocks", stub)).toBe(false);
  });

  it("never mistakes a producer's declared 'unavailable' for loading", () => {
    // The honesty line: this fallback carries a real widget id, so somebody reached this
    // conclusion. A skeleton here would outlive the truth.
    expect(isWidgetPending(undefined, "stocks", declared)).toBe(false);
  });

  it("has nothing to wait for when the slot is unassigned or is itself a stub id", () => {
    expect(isWidgetPending(undefined, undefined, stub)).toBe(false);
    expect(isWidgetPending(undefined, "", stub)).toBe(false);
    // A mode that assigns no widget leaves the stub id in the slot; waiting on a producer that
    // by definition does not exist would leave a permanent skeleton.
    expect(isWidgetPending(undefined, "left", stub)).toBe(false);
    expect(isWidgetPending(undefined, "right", stub)).toBe(false);
  });

  it("keeps the two stub ids out of the widget registry, which is what makes them safe", () => {
    // If a widget were ever registered as `left` or `right`, this predicate would silently start
    // reporting that widget as permanently loading. Assert the collision cannot happen.
    expect(WIDGET_IDS).not.toContain("left");
    expect(WIDGET_IDS).not.toContain("right");
  });

  it("treats real config/bootstrap data as an answer, not a silence", () => {
    const configured: WidgetData = { widgetId: "stocks", state: "empty", emptyMessage: "No data" };
    expect(isWidgetPending(undefined, "stocks", configured)).toBe(false);
  });
});
