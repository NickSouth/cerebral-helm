import type { UnreadFacts } from "./unreadCount";
import { composeDailyBrief, type DailyBriefSnapshot } from "./dailyBrief";
import { isRenderable, renderableBlocks, type ReportBlock } from "./reportDocument";

/** A measured whole-inbox count — an account that does not use Gmail's category tabs. */
const inbox = (count: number): UnreadFacts => ({ count, capped: false, scope: "inbox" });

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
    const withMail = composeDailyBrief(snapshot({ unreadCount: inbox(0) }));
    const count = withMail.blocks.find((block) => block.blockKind === "count");
    expect(count?.value).toBe("0");
    expect(count?.label).toBe("unread emails");
    expect(count?.reportAction).toEqual({ action: "open-mail" });
    // Singular reads correctly too.
    expect(
      composeDailyBrief(snapshot({ unreadCount: inbox(1) })).blocks.find((b) => b.blockKind === "count")
        ?.label
    ).toBe("unread email");
  });

  it("says which slice it counted when the account uses Gmail's category tabs", () => {
    // The brief lists nothing, so the label is the only place this can be said — and it must be,
    // because the number excludes promotions and would otherwise read as the whole inbox.
    const count = composeDailyBrief(
      snapshot({ unreadCount: { count: 12, capped: false, scope: "primary" } })
    ).blocks.find((block) => block.blockKind === "count");
    expect(count?.value).toBe("12");
    expect(count?.label).toBe("unread in Primary");
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

/**
 * NIC-228: the brief is two halves — a deterministic header that renders immediately, and a body
 * the model writes about nine seconds later.
 *
 * What these protect is the seam. The header must be identical in every state, because it is the
 * part a reader is already looking at while the rest is still being written; and an unavailable
 * composition must still produce a brief, because the app shipped with one and losing it to a
 * stopped daemon would be a regression rather than a degradation.
 */

const composedDocument = {
  schemaVersion: "1.0.0",
  reportId: "daily-brief",
  blocks: [
    { blockKind: "line", text: "Your investor call is the only fixed thing today." },
    { blockKind: "count", value: "3", label: "unread that look like they need you" }
  ]
} as const;

function headerTexts(document: { blocks: readonly ReportBlock[] }): string[] {
  return document.blocks.slice(0, 3).map((block) => block.text ?? block.value ?? "");
}

describe("the deterministic header", () => {
  it("is the same three blocks whatever the model is doing", () => {
    // Identical in every state, because it renders the instant the report opens and is never
    // rewritten. A header that changed when the body landed would be a visible rewrite of text the
    // reader had already started on.
    const snap = snapshot();
    const composing = composeDailyBrief(snap, { status: "composing", document: null, reason: null });
    const ready = composeDailyBrief(snap, { status: "ready", document: composedDocument, reason: null });
    const failed = composeDailyBrief(snap, {
      status: "unavailable", document: null, reason: "Ollama isn’t running."
    });

    expect(headerTexts(composing)).toEqual(headerTexts(ready));
    expect(headerTexts(ready)).toEqual(headerTexts(failed));
    expect(composing.blocks[0].blockKind).toBe("greeting");
  });

  it("states today's high, which is the number a morning actually turns on", () => {
    const document = composeDailyBrief(
      snapshot({ weather: { state: "ready", temperatureF: 63.4, condition: "Clear", highF: 78.2 } }),
      { status: "ready", document: composedDocument, reason: null }
    );

    // Appended rather than substituted: the current reading is still what you feel stepping outside.
    expect(document.blocks[2].value).toBe("63°F · Clear · high 78°");
  });

  it("omits the high when the provider supplied none", () => {
    const document = composeDailyBrief(
      snapshot({ weather: { state: "ready", temperatureF: 63.4, condition: "Clear" } }),
      { status: "ready", document: composedDocument, reason: null }
    );

    expect(document.blocks[2].value).toBe("63°F · Clear");
  });
});

describe("the composed body", () => {
  it("is the model's blocks, under the header", () => {
    const document = composeDailyBrief(snapshot(), {
      status: "ready", document: composedDocument, reason: null
    });

    expect(document.blocks).toHaveLength(5);
    expect(document.blocks[3].text).toBe("Your investor call is the only fixed thing today.");
    // The envelope is the system's in the web layer too: the model's `reportId` and `schemaVersion`
    // are not carried through from its document, they are set here.
    expect(document.reportId).toBe("daily-brief");
    expect(document.schemaVersion).toBe("1.0.0");
  });

  it("says something is happening while the model is writing", () => {
    // Nine seconds of a header and nothing else reads as a report that failed to load.
    const document = composeDailyBrief(snapshot(), {
      status: "composing", document: null, reason: null
    });

    expect(document.blocks).toHaveLength(4);
    expect(document.blocks[3].text).toBe("Writing your brief…");
    expect(document.blocks[3].lineEmphasis).toBe("muted");
  });

  it("falls back to the deterministic facts when no composition arrives", () => {
    // The degradation path, and the reason it exists: a stopped daemon must not cost the reader the
    // brief this app shipped with. The reason is stated, then the facts the web layer can state on
    // its own follow — a reason with no brief under it would be the worse report.
    const document = composeDailyBrief(
      snapshot({ unreadCount: inbox(4) }),
      { status: "unavailable", document: null, reason: "Ollama isn’t running." }
    );
    const texts = document.blocks.map((block) => block.text ?? block.label ?? "");

    expect(texts).toContain("Ollama isn’t running.");
    expect(document.blocks.some((block) => block.blockKind === "list")).toBe(true);
    expect(document.blocks.some((block) => block.blockKind === "count")).toBe(true);
  });

  it("is the deterministic formula outright when nothing asked for a composition", () => {
    // `null` is the pre-model call site — no composition was even attempted.
    const document = composeDailyBrief(snapshot({ unreadCount: inbox(4) }));

    expect(document.blocks.some((block) => block.blockKind === "list")).toBe(true);
    expect(renderableBlocks(document).length).toBe(document.blocks.length);
  });

  it("renders every state through the existing renderer without a malformed block", () => {
    // The renderer never changed, and it must not have to. A block it cannot draw is dropped, so a
    // state that produced one would render short rather than loudly — which is why this asserts
    // every block survives rather than trusting the shapes above.
    for (const composed of [
      null,
      { status: "composing", document: null, reason: null },
      { status: "ready", document: composedDocument, reason: null },
      { status: "unavailable", document: null, reason: "Ollama isn’t running." }
    ]) {
      const document = composeDailyBrief(snapshot({ unreadCount: inbox(2) }), composed);
      expect(document.blocks.every(isRenderable)).toBe(true);
    }
  });
});

describe("the refresh control", () => {
  it("is offered whenever a composition was attempted", () => {
    // A composition IS a fetch the reader can repeat — which the old ambient-state formula was not,
    // and which is why that control was withheld before. It matters most in the failure case: the
    // commonest reason a brief is unavailable is a daemon that was still starting.
    const snap = snapshot();
    for (const status of ["composing", "ready", "unavailable"] as const) {
      const document = composeDailyBrief(snap, {
        status,
        document: status === "ready" ? composedDocument : null,
        reason: status === "unavailable" ? "Ollama isn’t running." : null
      });
      expect(document.refreshable).toBe(true);
    }
  });

  it("is withheld when nothing asked for a composition", () => {
    // Nothing to re-run: offering the control would promise something it cannot do.
    expect(composeDailyBrief(snapshot()).refreshable).toBe(false);
  });
});
