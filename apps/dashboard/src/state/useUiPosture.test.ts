import { describe, it, expect } from "vitest";
import { deriveUiPosture } from "./useUiPosture";
import type { DashboardState } from "./dashboardState";
import { getDashboardConfigBundle, getDashboardFixture } from "../fixtures/canonicalFixtures";

/** A full dashboard state for a canonical key (bundle + snapshot), so posture reads real shapes. */
function stateFor(canonicalKey: string): DashboardState {
  return { ...getDashboardConfigBundle(), ...getDashboardFixture(canonicalKey) };
}

describe("deriveUiPosture (NIC-64)", () => {
  it("treats a ready dashboard as writable and un-degraded", () => {
    const posture = deriveUiPosture(stateFor("mode.executive.ready"));
    expect(posture).toMatchObject({
      loading: false,
      offline: false,
      error: false,
      recovering: false,
      readOnly: false,
      degraded: false
    });
  });

  it("maps the loading state to a first-paint posture (no read-only)", () => {
    const posture = deriveUiPosture(stateFor("system.dashboard.loading"));
    expect(posture.loading).toBe(true);
    expect(posture.degraded).toBe(true);
    expect(posture.readOnly).toBe(false);
  });

  it("makes offline read-only (live actions must be suppressed)", () => {
    const posture = deriveUiPosture(stateFor("failure.dashboard_offline"));
    expect(posture.offline).toBe(true);
    expect(posture.readOnly).toBe(true);
    expect(posture.degraded).toBe(true);
  });

  it("surfaces the error state without forcing read-only", () => {
    const posture = deriveUiPosture(stateFor("failure.dashboard_error"));
    expect(posture.error).toBe(true);
    expect(posture.degraded).toBe(true);
    expect(posture.readOnly).toBe(false);
  });

  it("treats a runtime recovery posture as read-only and carries its specific reason", () => {
    const base = stateFor("mode.executive.ready");
    const recovering: DashboardState = {
      ...base,
      recovery: { reason: "Bridge major version is incompatible.", startupMode: "recovery" }
    };
    const posture = deriveUiPosture(recovering);
    expect(posture.recovering).toBe(true);
    expect(posture.readOnly).toBe(true);
    expect(posture.recoveryReason).toBe("Bridge major version is incompatible.");
  });
});
