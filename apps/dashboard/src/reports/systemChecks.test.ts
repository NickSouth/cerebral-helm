import { describe, expect, it } from "vitest";
import { checkItem, composeSystemChecks, metricsRow, summaryLine } from "./systemChecks";
import type { SystemCheck, SystemChecksPayload } from "../bridge/cerebralBridge";

/** `system-status-checks`' composer (docs/quick-actions/PLAN.md phase 5). */

function check(overrides: Partial<SystemCheck> = {}): SystemCheck {
  return {
    id: "integration.linear",
    title: "Linear",
    group: "integrations",
    state: "passed",
    detail: "Answered.",
    ...overrides
  };
}

function payload(checks: SystemCheck[], complete = true): SystemChecksPayload {
  return { checks, complete, failureCount: checks.filter((c) => c.state === "failed").length };
}

describe("the summary line", () => {
  it("counts progress while the run is still going", () => {
    const block = summaryLine(
      payload([check(), check({ id: "b", state: "pending" })], false)
    );
    expect(block).toMatchObject({ value: "1/2", label: "checked so far" });
  });

  it("leads with what needs attention when anything failed", () => {
    const block = summaryLine(payload([check(), check({ id: "b", state: "failed" })]));
    expect(block).toMatchObject({ value: "1", label: "thing needs attention", metricTone: "critical" });
  });

  it("never rounds skipped checks up into an all-clear", () => {
    // A green line that quietly covered six unconfigured integrations would be the exact
    // dishonesty this surface exists to avoid.
    const block = summaryLine(
      payload([check(), check({ id: "b", state: "skipped", detail: "Not set up." })])
    );
    expect(block).toMatchObject({ value: "1", label: "checks passed · 1 not set up" });
  });

  it("says plainly when everything passed and nothing was skipped", () => {
    const block = summaryLine(payload([check(), check({ id: "b" })]));
    expect(block).toMatchObject({ value: "2", label: "checks passed", metricTone: "positive" });
  });
});

describe("a row", () => {
  it("carries what was actually established, not a bare verdict", () => {
    // The reader's next question is always "checked how?".
    expect(checkItem(check({ detail: "Key is set. Not contacted." })).text).toBe(
      "Linear — Key is set. Not contacted."
    );
  });

  it("puts the fix on the row, not behind a disclosure", () => {
    const item = checkItem(
      check({ state: "failed", detail: "Denied.", remediation: "System Settings → Accessibility." })
    );
    // A fix you have to click to see is a fix most people never read.
    expect(item.text).toBe("Linear — Denied. System Settings → Accessibility.");
    expect(item.status).toBe("failed");
  });

  it("shows a duration only once there is one to show", () => {
    expect(checkItem(check({ state: "pending", durationMs: null })).meta).toBeUndefined();
    expect(checkItem(check({ durationMs: 120 })).meta).toBe("120 ms");
  });
});

describe("the document", () => {
  it("distinguishes 'never run' from a run that found nothing", () => {
    const document = composeSystemChecks(null);
    expect(document.blocks).toEqual([{ blockKind: "empty", text: "Checking…" }]);
  });

  it("groups the rows, because each group is fixed in a different place", () => {
    const document = composeSystemChecks(
      payload([
        check({ id: "p", title: "Accessibility", group: "permissions" }),
        check({ id: "i", title: "Linear", group: "integrations" }),
        check({ id: "s", title: "Knowledge root", group: "storage" })
      ])
    );
    const headings = document.blocks
      .filter((block) => block.blockKind === "line")
      .map((block) => block.text);
    expect(headings).toEqual(["Permissions & apps", "Integrations", "Storage"]);
    // One checklist per group, and every row lands in exactly one.
    const lists = document.blocks.filter((block) => block.blockKind === "checklist");
    expect(lists).toHaveLength(3);
    expect(lists.every((list) => list.listItems?.length === 1)).toBe(true);
  });

  it("omits a group with nothing in it rather than showing an empty heading", () => {
    const document = composeSystemChecks(payload([check({ group: "storage" })]));
    const headings = document.blocks
      .filter((block) => block.blockKind === "line")
      .map((block) => block.text);
    expect(headings).toEqual(["Storage"]);
  });

  it("says so honestly on a host with nothing to check", () => {
    const document = composeSystemChecks(payload([]));
    expect(document.blocks.some((block) => block.blockKind === "empty")).toBe(true);
  });
});

describe("the live metrics header", () => {
  const health = {
    state: "ready" as const,
    cpuPercent: 18.4,
    memoryPercent: 50,
    network: { state: "ready" as const, linkMbps: 120 },
    battery: { state: "ready" as const, percent: 82, charging: true }
  };

  it("reads the channels the publisher actually has", () => {
    expect(metricsRow(health)).toMatchObject({
      blockKind: "metric",
      label: "Right now",
      value: "CPU 18%  ·  Memory 50%  ·  Network 120 Mbps  ·  Battery 82% ⚡"
    });
  });

  it("omits a channel with no reading rather than printing a zero", () => {
    // "0%" is a measurement. Printing one for a channel this Mac cannot report would be a
    // fabricated number in the one report whose whole purpose is telling the truth about it.
    const partial = metricsRow({ state: "ready" as const, cpuPercent: 3, battery: { state: "ready" as const } });
    expect(partial).toMatchObject({ value: "CPU 3%" });
  });

  it("renders nothing at all when the region is unavailable or empty", () => {
    expect(metricsRow(undefined)).toBeNull();
    expect(metricsRow({ state: "unavailable", battery: { state: "unavailable" } })).toBeNull();
    expect(metricsRow({ state: "ready", battery: { state: "ready" } })).toBeNull();
  });

  it("leads the document, so the top is current even while the checklist is mid-run", () => {
    const document = composeSystemChecks(payload([check()], false), health);
    expect(document.blocks[0]).toMatchObject({ blockKind: "metric", label: "Right now" });
    expect(document.blocks[1]).toMatchObject({ blockKind: "count" });
  });

  it("shows the metrics even before any run has happened", () => {
    // Opening the report should never be a blank panel: the machine's state is known instantly,
    // and only the checks take seconds.
    const document = composeSystemChecks(null, health);
    expect(document.blocks[0]).toMatchObject({ blockKind: "metric" });
    expect(document.blocks[1]).toMatchObject({ blockKind: "empty", text: "Checking…" });
  });
});
