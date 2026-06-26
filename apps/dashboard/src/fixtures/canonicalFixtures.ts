import catalog from "../../../../fixtures/catalog/canonical-states.json";
import type { DashboardBootstrapState } from "../bridge/types";

interface CanonicalFixture {
  readonly id: string;
  readonly canonicalKey: string;
  readonly category: string;
  readonly clock: string;
  readonly modeId: string;
  readonly dashboardState?: DashboardBootstrapState;
}

interface CanonicalFixtureCatalog {
  readonly schemaVersion: string;
  readonly fixtures: readonly CanonicalFixture[];
}

export const canonicalFixtureCatalog = catalog as CanonicalFixtureCatalog;

export const dashboardStoryFixtures = canonicalFixtureCatalog.fixtures.filter(
  (fixture): fixture is CanonicalFixture & { readonly dashboardState: DashboardBootstrapState } =>
    fixture.dashboardState !== undefined
);

export function getDashboardFixture(canonicalKey: string): DashboardBootstrapState {
  const fixture = dashboardStoryFixtures.find((candidate) => candidate.canonicalKey === canonicalKey);

  if (!fixture) {
    throw new Error(`Missing dashboard fixture: ${canonicalKey}`);
  }

  return fixture.dashboardState;
}
