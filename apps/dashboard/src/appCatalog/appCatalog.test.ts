import { APP_CATALOG, APP_IDS, isRegisteredAppId } from "./appCatalog";
import manifest from "./appCatalog.manifest.json";

describe("application catalog", () => {
  it("keeps appCatalog.manifest.json in lockstep with APP_IDS (the gate reads the manifest)", () => {
    expect(manifest.appIds).toEqual([...APP_IDS]);
  });

  it("registers unique, non-empty app ids and labels", () => {
    expect(APP_IDS.length).toBeGreaterThan(0);
    expect(new Set(APP_IDS).size).toBe(APP_IDS.length);
    for (const app of APP_CATALOG) {
      expect(app.id.length).toBeGreaterThan(0);
      expect(app.label.length).toBeGreaterThan(0);
    }
  });

  it("recognizes registered ids and rejects unknown ones", () => {
    expect(isRegisteredAppId("chrome")).toBe(true);
    expect(isRegisteredAppId("myspace")).toBe(false);
  });
});
