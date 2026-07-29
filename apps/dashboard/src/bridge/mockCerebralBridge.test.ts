import { createMockCerebralBridge } from "./mockCerebralBridge";
import type { BridgeEvent } from "./cerebralBridge";

const NOISE_EVENT: BridgeEvent = {
  eventId: "brevt_testnoise01",
  type: "config.changed",
  schemaVersion: "1.0.0",
  timestamp: "2026-06-23T16:00:00.000Z",
  payload: {}
};

describe("MockCerebralBridge", () => {
  it("returns a composed bootstrap state through the bridge contract", async () => {
    const bridge = createMockCerebralBridge();
    const state = await bridge.getBootstrapState();

    expect(state.mode).toBe("Executive"); // Executive is the default mode (ADR-007).
    expect(state.modes).toHaveLength(4);
    expect(state.agents).toHaveLength(4);
    expect(state.expandedAgent).toBeNull();
    expect(state.regions.systemHealth.battery.state).toBe("ready");
    expect(state.regions.systemHealth.battery.percent).toBe(82);
  });

  it("can boot a different canonical state by key", async () => {
    const bridge = createMockCerebralBridge({ bootstrapKey: "mode.school.ready" });
    expect((await bridge.getBootstrapState()).mode).toBe("School");
  });

  it("emits a config.changed snapshot when a mode is applied", async () => {
    const bridge = createMockCerebralBridge();
    const events: BridgeEvent[] = [];
    bridge.subscribe((event) => events.push(event));

    const result = await bridge.applyMode({ modeId: "school" });

    expect(result.status).toBe("ok");
    const configEvent = events.find((event) => event.type === "config.changed");
    expect(configEvent).toBeDefined();
    expect((configEvent?.payload as { snapshot: { mode: string } }).snapshot.mode).toBe("School");
  });

  it("delivers events to subscribers and stops after unsubscribe", () => {
    const bridge = createMockCerebralBridge();
    const received: BridgeEvent[] = [];

    const unsubscribe = bridge.subscribe((event) => received.push(event));
    bridge.emit(NOISE_EVENT);
    expect(received).toHaveLength(1);

    unsubscribe();
    bridge.emit(NOISE_EVENT);
    expect(received).toHaveLength(1);
  });

  it("replays every canonical command-lifecycle transition", () => {
    const bridge = createMockCerebralBridge();
    const events: BridgeEvent[] = [];
    bridge.subscribe((event) => events.push(event));

    bridge.replayLifecycle();

    expect(events).toHaveLength(9);
    expect(events.every((event) => event.type === "command.lifecycle.transition")).toBe(true);

    const statuses = new Set(
      events.map((event) => (event.payload as { currentStatus: string }).currentStatus)
    );
    for (const status of [
      "received",
      "planned",
      "running",
      "requires_confirmation",
      "succeeded",
      "failed",
      "cancelled"
    ]) {
      expect(statuses.has(status)).toBe(true);
    }
  });

  it("replays the capability change and every canonical failure state", () => {
    const bridge = createMockCerebralBridge();
    const events: BridgeEvent[] = [];
    bridge.subscribe((event) => events.push(event));

    bridge.replayFailures();

    // One capability event plus every state-bearing canonical fixture.
    expect(events.length).toBeGreaterThanOrEqual(10);
    expect(events.some((event) => event.type === "bridge.capability.changed")).toBe(true);
    expect(events.some((event) => event.type === "system.status.changed")).toBe(true);
  });

  it("replays a confirmation disclosure and clears it on a decision", async () => {
    const bridge = createMockCerebralBridge();
    const events: BridgeEvent[] = [];
    bridge.subscribe((event) => events.push(event));

    bridge.replayConfirmation();
    const shown = events.find((event) => event.type === "confirmation.changed");
    expect((shown?.payload as { confirmation?: { id: string } }).confirmation?.id).toBe(
      "conf_000000000000000000000001"
    );

    await bridge.decideConfirmation({ id: "conf_000000000000000000000001", decision: "approve" });
    const last = events.filter((event) => event.type === "confirmation.changed").at(-1);
    expect((last?.payload as { confirmation: unknown }).confirmation).toBeNull();
  });

  it("returns fixture-shaped operation responses", async () => {
    const bridge = createMockCerebralBridge();

    expect(
      (await bridge.submitCommand({ rawInput: "mode developer", source: "dashboard" })).accepted
    ).toBe(true);
    expect((await bridge.applyMode({ modeId: "school" })).modeId).toBe("school");
    expect((await bridge.decideConfirmation({ id: "conf_1", decision: "cancel" })).decision).toBe(
      "cancel"
    );

    const activity = await bridge.getRecentActivity();
    expect(activity.commands.length).toBeGreaterThanOrEqual(1);
    expect(activity.errors.length).toBeGreaterThanOrEqual(1);
  });

  it("mints a URL reference through addUrlReference and lists + pins it (NIC-146)", async () => {
    const bridge = createMockCerebralBridge();
    const added = await bridge.addUrlReference({
      url: "https://news.ycombinator.com",
      label: "Hacker News"
    });
    expect(added.accepted).toBe(true);
    expect(added.reference?.id).toBe("hacker-news");
    expect(added.reference?.target).toBe("https://news.ycombinator.com");

    const listed = await bridge.listUrls();
    const ids = listed.urls.map((url) => url.id);
    expect(ids).toContain("hacker-news"); // minted
    expect(ids).toContain("github"); // shipped catalog is included

    // The minted id pins through the same slot validation an app id clears.
    const pin = await bridge.updateQuickApps({ modeId: "developer", quickApps: ["hacker-news"] });
    expect(pin.accepted).toBe(true);
  });

  it("addUrlReference carries a Chrome profile; same URL under different profiles is distinct (NIC-151)", async () => {
    const bridge = createMockCerebralBridge();
    const work = await bridge.addUrlReference({
      url: "https://mail.google.com",
      label: "Work Mail",
      profile: "Profile 1"
    });
    expect(work.reference?.profile).toBe("Profile 1");

    const personal = await bridge.addUrlReference({
      url: "https://mail.google.com",
      label: "Personal Mail",
      profile: "Default"
    });
    expect(personal.reference?.profile).toBe("Default");
    // Same target, different profile → a distinct pin, not a collapse to the first.
    expect(personal.reference?.id).not.toBe(work.reference?.id);

    const listed = await bridge.listUrls();
    expect(listed.urls.filter((url) => url.target === "https://mail.google.com").length).toBe(2);
  });

  it("addUrlReference rejects a flag-injecting Chrome profile without minting (NIC-151)", async () => {
    const bridge = createMockCerebralBridge();
    const result = await bridge.addUrlReference({
      url: "https://mail.google.com",
      profile: "Default --load-extension=/tmp/evil"
    });
    expect(result.accepted).toBe(false);
    expect(result.reference).toBeNull();
    expect(result.errors[0]).toMatch(/Chrome profile/);
    expect((await bridge.listUrls()).urls.some((url) => url.target === "https://mail.google.com")).toBe(
      false
    );
  });

  it("lists Chrome profiles and mints a pinnable Chrome-profile reference (NIC-151)", async () => {
    const bridge = createMockCerebralBridge();
    const listed = await bridge.listChromeProfiles();
    expect(listed.profiles.map((p) => p.directory)).toContain("Profile 1");
    expect(listed.references).toHaveLength(0);

    const added = await bridge.addChromeProfileReference({ directory: "Profile 1", name: "Work" });
    expect(added.accepted).toBe(true);
    expect(added.reference?.target).toBe("com.google.Chrome");
    expect(added.reference?.profile).toBe("Profile 1");

    // The pinned reference now surfaces in listChromeProfiles, and re-pinning is idempotent.
    const after = await bridge.listChromeProfiles();
    expect(after.references.map((r) => r.id)).toEqual([added.reference?.id]);
    const again = await bridge.addChromeProfileReference({ directory: "Profile 1", name: "Work" });
    expect(again.reference?.id).toBe(added.reference?.id);
    expect((await bridge.listChromeProfiles()).references).toHaveLength(1);
  });

  it("addUrlReference refuses a non-web scheme without minting (NIC-146)", async () => {
    const bridge = createMockCerebralBridge();
    const result = await bridge.addUrlReference({ url: "file:///etc/passwd" });
    expect(result.accepted).toBe(false);
    expect(result.reference).toBeNull();
    expect(result.errors[0]).toMatch(/http and https/);

    // A scheme-less host still mints (defaults to https); the catalog stays web-only.
    expect((await bridge.addUrlReference({ url: "example.com" })).reference?.target).toBe(
      "https://example.com"
    );
    expect((await bridge.listUrls()).urls.every((url) => url.target.startsWith("http"))).toBe(true);
  });

  it("getSettings returns a resolved snapshot with representative non-default values (NIC-141)", async () => {
    const bridge = createMockCerebralBridge();
    const settings = await bridge.getSettings();

    // Non-default so the settings UI visibly proves it reads persisted state.
    expect(settings.defaultModeId).toBe("developer");
    expect(settings.workspace.windowsStoredByMode).toBe(true);
    expect(settings.knowledge.rootReference).toBe("knowledge-root");
    // Every field is resolved (present), not optional.
    expect(settings.appearance.reducedMotion).toBe(false);
    expect(settings.appearance.assistantName).toBe("Heimlich");
    expect(settings.confirmAllActions).toBe(false);
    expect(settings.modeColors).toEqual({});
    expect(settings.calendarModeMap).toEqual({});
    expect(settings.workspace.mainDisplayId).toBe("system-primary");
    expect(settings.schemaVersion).toBe("1.0.0");
  });
});
