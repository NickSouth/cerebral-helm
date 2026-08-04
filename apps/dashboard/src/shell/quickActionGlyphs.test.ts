import { describe, expect, it } from "vitest";
import { isQuickActionGlyphName } from "./QuickActionGlyph";
import { quickActionEntries } from "./quickActionRegistry";

/**
 * The registry names an icon per action; `QuickActionGlyph` draws it. Nothing in the config gate can
 * check that seam — it validates the name is a non-empty string, but only TypeScript knows which
 * names have drawings. This closes it: a new action whose icon has no glyph fails here rather than
 * rendering a slot with a missing leading icon.
 */
describe("quick action glyphs", () => {
  const entries = Object.entries(quickActionEntries());

  it("covers every registered action's icon", () => {
    const missing = entries
      .filter(([, entry]) => !isQuickActionGlyphName(entry.icon))
      .map(([id, entry]) => `${id} -> ${entry.icon}`);

    expect(missing).toEqual([]);
  });

  it("registers an icon for every action", () => {
    expect(entries.length).toBeGreaterThan(0);
    for (const [id, entry] of entries) {
      expect(entry.icon, `action "${id}" must declare an icon`).toBeTruthy();
    }
  });
});
