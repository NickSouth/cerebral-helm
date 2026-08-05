import { signalLevelFromRssi } from "./HealthGlyph";

describe("signalLevelFromRssi (NIC-156)", () => {
  it("maps dBm onto the three arc levels at the conventional boundaries", () => {
    expect(signalLevelFromRssi(-35)).toBe(3);
    expect(signalLevelFromRssi(-60)).toBe(3);
    expect(signalLevelFromRssi(-61)).toBe(2);
    expect(signalLevelFromRssi(-75)).toBe(2);
    expect(signalLevelFromRssi(-76)).toBe(1);
    expect(signalLevelFromRssi(-95)).toBe(1);
  });

  it("returns nothing for an absent reading, so nothing dims", () => {
    // "We did not measure this" must not render as "the signal is weak".
    expect(signalLevelFromRssi(undefined)).toBeUndefined();
  });

  it("rejects non-finite values rather than dimming off a NaN", () => {
    expect(signalLevelFromRssi(Number.NaN)).toBeUndefined();
    expect(signalLevelFromRssi(Number.NEGATIVE_INFINITY)).toBeUndefined();
  });
});
