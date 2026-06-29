import catalog from "../../../../fixtures/catalog/canonical-states.json";
import configBundle from "./dashboardConfig.fixtures.json";
import type { DashboardConfigBundle, DashboardStateSnapshot } from "../bridge/types";

interface CanonicalFixture {
  readonly id: string;
  readonly canonicalKey: string;
  readonly category: string;
  readonly clock: string;
  readonly modeId: string;
  readonly dashboardState?: DashboardStateSnapshot;
}

interface CanonicalFixtureCatalog {
  readonly schemaVersion: string;
  readonly fixtures: readonly CanonicalFixture[];
}

export const canonicalFixtureCatalog = catalog as CanonicalFixtureCatalog;

export const dashboardStoryFixtures = canonicalFixtureCatalog.fixtures.filter(
  (fixture): fixture is CanonicalFixture & { readonly dashboardState: DashboardStateSnapshot } =>
    fixture.dashboardState !== undefined
);

/**
 * The per-state snapshot for a canonical key (active mode view + regions + summary
 * fields). Compose with getDashboardConfigBundle() for a full bootstrap state.
 */
export function getDashboardFixture(canonicalKey: string): DashboardStateSnapshot {
  const fixture = dashboardStoryFixtures.find((candidate) => candidate.canonicalKey === canonicalKey);

  if (!fixture) {
    throw new Error(`Missing dashboard fixture: ${canonicalKey}`);
  }

  return fixture.dashboardState;
}

/**
 * The eager, mode-independent config bundle: all four resolved mode views (so a switch
 * re-themes with no flash) plus the fixed agent roster. The bridge ships this once; the
 * mock composes it with a per-state snapshot.
 */
export function getDashboardConfigBundle(): DashboardConfigBundle {
  return configBundle as DashboardConfigBundle;
}
