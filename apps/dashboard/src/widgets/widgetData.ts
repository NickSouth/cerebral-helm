/**
 * Common widget-data envelope. Design spec §5.3: each widget surfaces its own data,
 * an empty state, a freshness indicator, and an optional action — a named slot, not a
 * per-mode conditional. The per-widget payload under `data` is widget-specific and
 * demonstrated by the fixtures in ./fixtures/widgetData.fixtures.json.
 *
 * This envelope is the shape NIC-52 (the expanded DashboardBootstrapState, NIC-117 d)
 * lifts so the bridge can deliver widget data across the boundary. Pre-bridge it backs
 * the fixture-rendered widget slots in NIC-54.
 */

import type { WidgetId } from "./widgets";

export type WidgetState = "ready" | "empty" | "stale" | "unavailable";

export interface WidgetFreshness {
  /** ISO-8601 instant the data was observed. */
  readonly observedAt: string;
  /** Short human label, e.g. "2m ago". */
  readonly label: string;
}

export interface WidgetAction {
  readonly id: string;
  readonly label: string;
}

export interface WidgetData<TPayload = unknown> {
  readonly widgetId: WidgetId;
  readonly state: WidgetState;
  /** Present when state is "ready" (and may accompany "stale"). */
  readonly headline?: string;
  /** Widget-specific payload; shape demonstrated by the fixtures. */
  readonly data?: TPayload;
  readonly freshness?: WidgetFreshness;
  /** Shown when state is "empty" or "unavailable" — an honest, specific message. */
  readonly emptyMessage?: string;
  readonly action?: WidgetAction;
}
