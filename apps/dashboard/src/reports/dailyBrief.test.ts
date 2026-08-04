import { composeDailyBrief, type DailyBriefSnapshot } from "./dailyBrief";
import { isRenderable, renderableBlocks, type ReportBlock } from "./reportDocument";

/**
 * The v1 composer is the deterministic stand-in for a model, so what matters is that it is
 * genuinely deterministic and that it never states something it does not know.
 */

const MORNING = new Date("2026-08-03T09:15:00");

function snapshot(overrides: Partial<DailyBriefSnapshot> = {}): DailyBriefSnapshot {
  return {
    now: MORNING,
    weather: { state: "ready", temperatureF: 72.4, condition: "Partly cloudy" },
    schedule: {
      state: "ready",
      items: [
        { id: "e1", title: "Board prep review", start: "2026-08-03T17:00:00Z", kind: "today" },
        { id: "e2", title: "Investor call", start: "2026-08-03T17:30:00Z", kind: "today" }
      ]
    },
    unreadCount: null,
    ...overrides
  };
}

function kinds(blocks: readonly ReportBlock[]): string[] {
  return blocks.map((block) => block.blockKind);
}

describe("composeDailyBrief", () => {
  it("is deterministic — the same snapshot always yields an identical document", () => {
    expect(composeDailyBrief(snapshot())).toEqual(composeDailyBrief(snapshot()));
  });

  it("composes the v1 formula: greeting, time, weather, calendar", () => {
    const document = composeDailyBrief(snapshot());
    expect(document.reportId).toBe("daily-brief");
    expect(kinds(document.blocks)).toEqual(["greeting", "line", "metric", "list"]);
    expect(document.blocks[0].text).toBe("Good morning.");
    expect(document.blocks[2].value).toBe("72°F · Partly cloudy");
    expect(document.blocks[3].listItems?.map((item) => item.text)).toEqual([
      "Board prep review",
      "Investor call"
    ]);
  });

  it("greets by time of day", () => {
    const at = (iso: string) => composeDailyBrief(snapshot({ now: new Date(iso) })).blocks[0].text;
    expect(at("2026-08-03T09:15:00")).toBe("Good morning.");
    expect(at("2026-08-03T13:00:00")).toBe("Good afternoon.");
    expect(at("2026-08-03T20:00:00")).toBe("Good evening.");
  });

  it("omits the unread count entirely rather than claiming zero", () => {
    // No mail provider exists yet. "0 unread" would be a claim we cannot make.
    expect(kinds(composeDailyBrief(snapshot()).blocks)).not.toContain("count");

    // A real read of zero IS worth stating, and it links onward.
    const withMail = composeDailyBrief(snapshot({ unreadCount: 0 }));
    const count = withMail.blocks.find((block) => block.blockKind === "count");
    expect(count?.value).toBe("0");
    expect(count?.label).toBe("unread emails");
    expect(count?.reportAction).toEqual({ action: "email-report" });
    // Singular reads correctly too.
    expect(
      composeDailyBrief(snapshot({ unreadCount: 1 })).blocks.find((b) => b.blockKind === "count")
        ?.label
    ).toBe("unread email");
  });

  it("says nothing about weather that was never configured, and 'Unavailable' when it failed", () => {
    expect(kinds(composeDailyBrief(snapshot({ weather: null })).blocks)).not.toContain("metric");

    const failed = composeDailyBrief(snapshot({ weather: { state: "unavailable" } }));
    const metric = failed.blocks.find((block) => block.blockKind === "metric");
    expect(metric?.value).toBe("Unavailable");
    expect(metric?.metricTone).toBe("warning");
  });

  it("distinguishes an empty calendar from an unreadable one", () => {
    const empty = composeDailyBrief(snapshot({ schedule: { state: "ready", items: [] } }));
    expect(empty.blocks.find((block) => block.blockKind === "empty")?.text).toBe(
      "Nothing scheduled today."
    );

    // Rendering an unavailable calendar as "nothing scheduled" would be a quiet lie.
    const broken = composeDailyBrief(snapshot({ schedule: { state: "unavailable", items: [] } }));
    expect(kinds(broken.blocks)).not.toContain("empty");
    const line = broken.blocks.filter((block) => block.blockKind === "line").at(-1);
    expect(line?.text).toBe("Your calendar is unavailable.");
    expect(line?.lineEmphasis).toBe("muted");
  });

  it("emits only blocks the renderer can draw", () => {
    for (const block of composeDailyBrief(snapshot()).blocks) {
      expect(isRenderable(block)).toBe(true);
    }
  });
});

describe("renderableBlocks", () => {
  it("drops malformed and unknown blocks instead of rendering them", () => {
    // A model will write these documents eventually; a half-formed block must shorten the
    // report, never blank it or throw.
    const document = {
      schemaVersion: "1.0.0",
      reportId: "daily-brief",
      blocks: [
        { blockKind: "greeting", text: "Good morning." },
        { blockKind: "greeting", text: "   " },
        { blockKind: "metric", label: "Outside" },
        { blockKind: "list", listItems: [] },
        { blockKind: "invented-kind", text: "hello" },
        { blockKind: "line", text: "Still here." }
      ] as ReportBlock[]
    };

    expect(renderableBlocks(document).map((block) => block.text)).toEqual([
      "Good morning.",
      "Still here."
    ]);
  });
});
