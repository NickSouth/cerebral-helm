import { describe, it, expect } from "vitest";
import { buildSettingsPatch, validateSettingsChanges } from "./settingsPatch";

describe("validateSettingsChanges (NIC-63 — the shared config validation path)", () => {
  it("accepts the allowed editable changes", () => {
    expect(validateSettingsChanges({ defaultModeId: "developer" }).valid).toBe(true);
    expect(validateSettingsChanges({ appearance: { reducedMotion: true } }).valid).toBe(true);
    expect(validateSettingsChanges({ knowledge: { rootReference: "knowledge-root" } }).valid).toBe(true);
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
});
