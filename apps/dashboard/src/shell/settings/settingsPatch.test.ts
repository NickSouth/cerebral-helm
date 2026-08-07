import { describe, it, expect } from "vitest";
import { buildSettingsPatch, validateSettingsChanges } from "./settingsPatch";

describe("validateSettingsChanges (NIC-63 — the shared config validation path)", () => {
  it("accepts the allowed editable changes", () => {
    expect(validateSettingsChanges({ defaultModeId: "developer" }).valid).toBe(true);
    expect(validateSettingsChanges({ appearance: { reducedMotion: true } }).valid).toBe(true);
    expect(validateSettingsChanges({ knowledge: { rootReference: "knowledge-root" } }).valid).toBe(
      true
    );
  });

  it("rejects a risk override — permission policy cannot be weakened through settings", () => {
    // Mirrors packages/contracts/fixtures/invalid/config/settings/risk-override-patch.json.
    const result = validateSettingsChanges({ toolRiskOverrides: { "hook.run": "read_only" } });
    expect(result.valid).toBe(false);
    expect(result.errors.join(" ")).toMatch(/toolRiskOverrides/);
  });

  it("rejects an unknown default mode id and a bad density enum", () => {
    expect(validateSettingsChanges({ defaultModeId: "NOT VALID" }).valid).toBe(false);
    expect(validateSettingsChanges({ appearance: { density: "roomy" } }).valid).toBe(false);
  });

  it("builds a schema-shaped patch (versioned id + changes)", () => {
    const patch = buildSettingsPatch({ defaultModeId: "school" });
    expect(patch.schemaVersion).toBe("1.0.0");
    expect(patch.patchId).toMatch(/^set_[A-Za-z0-9_-]{8,64}$/);
    expect(patch.changes).toEqual({ defaultModeId: "school" });
  });

  it("accepts a valid stocks ticker list, including an empty (cleared) one (NIC-128)", () => {
    expect(validateSettingsChanges({ stocks: { tickers: ["SPY", "AAPL", "BRK.B"] } }).valid).toBe(true);
    expect(validateSettingsChanges({ stocks: { tickers: [] } }).valid).toBe(true);
  });

  it("rejects a malformed ticker symbol, an over-cap list, and an unknown stocks key (NIC-128)", () => {
    expect(validateSettingsChanges({ stocks: { tickers: ["not a symbol"] } }).valid).toBe(false);
    expect(validateSettingsChanges({ stocks: { tickers: ["1BAD"] } }).valid).toBe(false);
    const overCap = Array.from({ length: 21 }, (_, i) => `T${i}`);
    expect(validateSettingsChanges({ stocks: { tickers: overCap } }).valid).toBe(false);
    expect(validateSettingsChanges({ stocks: { watchlist: ["SPY"] } }).valid).toBe(false);
  });

  it("accepts a valid calendar→mode map, including an empty (cleared) one (NIC-126)", () => {
    expect(
      validateSettingsChanges({ calendarModeMap: { "cal-work": "executive", "cal-dev": "developer" } }).valid
    ).toBe(true);
    expect(validateSettingsChanges({ calendarModeMap: {} }).valid).toBe(true);
  });

  it("rejects a calendar mapped to an unknown mode, and a non-string value (NIC-126)", () => {
    expect(validateSettingsChanges({ calendarModeMap: { "cal-x": "cosmic" } }).valid).toBe(false);
    expect(validateSettingsChanges({ calendarModeMap: { "cal-x": 3 as unknown as string } }).valid).toBe(false);
  });
});
