import { describe, expect, it } from "vitest";
import { composeEmailReport, countBlock, messageItem, MAX_LISTED } from "./emailReport";
import type { UnreadFacts } from "./unreadCount";

/** A measured Primary count — what the live channel reports for a categorized account. */
const primary = (count: number): UnreadFacts => ({ count, capped: false, scope: "primary" });
/** A measured whole-inbox count — an account that does not use Gmail's category tabs. */
const inbox = (count: number): UnreadFacts => ({ count, capped: false, scope: "inbox" });
import type { UnreadMailItem, UnreadMailResult } from "../bridge/cerebralBridge";

/** `email-report` (Gmail integration) — the last of the 26 slots. */

function message(overrides: Partial<UnreadMailItem> = {}): UnreadMailItem {
  return {
    id: "1",
    byline: "Mum",
    subject: "Sunday lunch?",
    receivedAt: "2026-08-04T15:02:00Z",
    messageId: "abc@mail.example",
    ...overrides
  };
}

function ready(messages: UnreadMailItem[]): UnreadMailResult {
  return { state: "ready", messages, reason: null };
}

describe("a message row", () => {
  it("leads with the subject and bylines the sender", () => {
    expect(messageItem(message()).text).toBe("Sunday lunch? — Mum");
  });

  it("links through an action reference carrying the Message-ID, never a URL", () => {
    // Once a model composes this document every clickable thing in it is a model-chosen
    // destination, so the row names an ACTION and the tool builds the address host-side.
    expect(messageItem(message()).reportAction).toEqual({
      action: "open-mail",
      params: { messageId: "abc@mail.example" }
    });
  });

  it("renders as plain text when the sender omitted a Message-ID", () => {
    // A dead link is worse than an honest non-link.
    expect(messageItem(message({ messageId: null })).reportAction).toBeUndefined();
  });
});

describe("the count line", () => {
  it("reports the total and says how many are shown, so no arithmetic is needed", () => {
    expect(countBlock(primary(12), 5)).toMatchObject({
      value: "12",
      label: "unread in Primary · showing the 5 most recent"
    });
  });

  it("names the slice it counted, because Primary is not the whole inbox", () => {
    // "3 unread emails" would be false for an account holding 300 promotions.
    expect(countBlock(primary(3), 3)).toMatchObject({ value: "3", label: "unread in Primary" });
  });

  it("reads plainly when the account does not categorize and the count is everything", () => {
    expect(countBlock(inbox(3), 3)).toMatchObject({ value: "3", label: "unread emails" });
    expect(countBlock(inbox(1), 1)).toMatchObject({ value: "1", label: "unread email" });
  });

  it("shows a capped count as a floor, never as an exact total", () => {
    // The host counted to its ceiling and stopped; "100" would claim a precision it never had.
    expect(countBlock({ count: 100, capped: true, scope: "primary" }, 5)).toMatchObject({
      value: "100+",
      label: "unread in Primary · showing the 5 most recent"
    });
  });

  it("renders nothing when no count was measured", () => {
    // Never a fabricated zero: not measured and none unread are different facts.
    expect(countBlock(null, 0)).toBeNull();
  });

  it("opens the inbox, like the daily brief's count", () => {
    expect(countBlock(inbox(4), 4)?.reportAction).toEqual({ action: "open-mail" });
  });
});

describe("the document", () => {
  it("caps the list at five and lets the count carry the rest", () => {
    const many = Array.from({ length: 9 }, (_, index) => message({ id: String(index) }));
    const document = composeEmailReport({ mail: ready(many), unread: primary(12), loading: false });
    const list = document.blocks.find((block) => block.blockKind === "list");
    expect(list?.listItems).toHaveLength(MAX_LISTED);
    expect(document.blocks.at(-1)).toMatchObject({ value: "12" });
  });

  it("drops the Primary wording when the account does not categorize", () => {
    const document = composeEmailReport({ mail: ready([]), unread: inbox(0), loading: false });
    expect(document.blocks[0].text).toBe("Nothing unread — open your inbox");
  });

  it("counts from the live channel, not the capped list", () => {
    // Counting rows would report "5 unread" for an inbox holding fifty.
    const many = Array.from({ length: 5 }, (_, index) => message({ id: String(index) }));
    const document = composeEmailReport({ mail: ready(many), unread: primary(50), loading: false });
    expect(document.blocks.at(-1)).toMatchObject({ value: "50" });
  });

  it("says the inbox is clear rather than showing nothing, and still links onward", () => {
    const document = composeEmailReport({ mail: ready([]), unread: primary(0), loading: false });
    // Names the slice: an inbox holding a hundred unread promotions is not "clear", and saying so
    // flatly would be the report's least believable moment.
    expect(document.blocks[0].text).toBe("Nothing unread in Primary — open your inbox");
    // The one thing still worth doing from here is going to look anyway (owner, 2026-08-04).
    expect(document.blocks[0].reportAction).toEqual({ action: "open-mail" });
    // No redundant "0" underneath — the words already said it.
    expect(document.blocks).toHaveLength(1);
  });

  it("distinguishes not connected, not readable, and not yet read", () => {
    const notConnected = composeEmailReport({
      mail: { state: "not-connected", messages: [], reason: null }, unread: null, loading: false
    });
    expect(notConnected.blocks[0].text).toContain("isn’t connected");

    // A lapsed grant carries its own remedy, which is not the same as "connect".
    const reconnect = composeEmailReport({
      mail: { state: "reconnect", messages: [], reason: "Gmail needs reconnecting — Settings → Setup." },
      unread: null, loading: false
    });
    expect(reconnect.blocks[0].text).toContain("reconnecting");

    // And "still reading" is not "nothing there".
    const loading = composeEmailReport({ mail: null, unread: null, loading: true });
    expect(loading.blocks[0].text).toContain("Reading");
  });

  it("is refreshable — mail moves on, which is when you want it again", () => {
    expect(composeEmailReport({ mail: ready([]), unread: primary(0), loading: false }).refreshable).toBe(true);
  });
});

describe("the model composition (NIC-259)", () => {
  const snapshot = { mail: ready([message()]), unread: primary(3), loading: false };

  it("shows the model's summary when it is ready, not the deterministic list", () => {
    const document = composeEmailReport(snapshot, {
      status: "ready",
      blocks: [{ blockKind: "line", text: "Dana needs a reply on the capstone room by Wednesday." }],
      reason: null
    });
    expect(document.blocks).toHaveLength(1);
    expect(document.blocks[0].text).toContain("Dana");
    // The deterministic list did not run — a model summary replaces it, it does not sit beside it.
    expect(document.blocks.some((b) => b.blockKind === "list")).toBe(false);
  });

  it("streams the blocks it has so far while composing", () => {
    const document = composeEmailReport(snapshot, {
      status: "composing",
      blocks: [{ blockKind: "line", text: "First summary…" }],
      reason: null
    });
    expect(document.blocks[0].text).toBe("First summary…");
  });

  it("shows a reading line in the silence before the first block", () => {
    const document = composeEmailReport(snapshot, { status: "composing", blocks: [], reason: null });
    expect(document.blocks[0].text).toContain("Reading");
  });

  it("falls back to the deterministic list when composition is unavailable, reason first", () => {
    const document = composeEmailReport(snapshot, {
      status: "unavailable",
      blocks: [],
      reason: "The model runtime is not running."
    });
    // The reason is stated, then the honest list the bridge can build without a model.
    expect(document.blocks[0].text).toContain("not running");
    expect(document.blocks.some((b) => b.blockKind === "list")).toBe(true);
  });

  it("keeps the old signature: no composition means the deterministic list", () => {
    const document = composeEmailReport(snapshot);
    expect(document.blocks.some((b) => b.blockKind === "list")).toBe(true);
  });
});
