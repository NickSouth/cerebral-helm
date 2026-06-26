import type { DashboardBootstrapState } from "./types";
import { getDashboardFixture } from "../fixtures/canonicalFixtures";

const bootstrapState = getDashboardFixture("mode.developer.ready");

export function loadBootstrapState(): DashboardBootstrapState {
  return bootstrapState;
}
