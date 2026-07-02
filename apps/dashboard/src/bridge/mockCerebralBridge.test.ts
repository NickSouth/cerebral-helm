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
});
