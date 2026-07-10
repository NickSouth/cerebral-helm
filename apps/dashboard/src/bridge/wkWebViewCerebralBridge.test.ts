import { afterEach, describe, expect, it } from "vitest";
import {
  createWKWebViewCerebralBridge,
  isNativeBridgeAvailable,
  readInjectedBootstrap
} from "./wkWebViewCerebralBridge";
import type { BridgeEvent } from "./cerebralBridge";

interface TestWindow {
  webkit?: { messageHandlers?: { cerebral?: { postMessage: (m: string) => void } } };
  __cerebralReceive?: (json: string) => void;
  __cerebralBootstrap?: unknown;
}

const win = window as unknown as TestWindow;

function installChannel(): { sent: Array<Record<string, unknown>> } {
  const sent: Array<Record<string, unknown>> = [];
  win.webkit = {
    messageHandlers: { cerebral: { postMessage: (m: string) => sent.push(JSON.parse(m)) } }
  };
  return { sent };
}

function reply(message: Record<string, unknown>): void {
  win.__cerebralReceive?.(JSON.stringify(message));
}

afterEach(() => {
  delete win.webkit;
  delete win.__cerebralReceive;
  delete win.__cerebralBootstrap;
});

describe("wkWebViewCerebralBridge", () => {
  it("detects the native channel and reads the injected bootstrap", () => {
    expect(isNativeBridgeAvailable()).toBe(false);
    installChannel();
    expect(isNativeBridgeAvailable()).toBe(true);
    win.__cerebralBootstrap = { mode: "Executive" };
    expect(readInjectedBootstrap()).toEqual({ mode: "Executive" });
  });

  it("announces a handshake on construction", () => {
    const { sent } = installChannel();
    createWKWebViewCerebralBridge();
    const handshake = sent.find((m) => m.type === "bridge.handshake.request");
    expect(handshake).toBeTruthy();
    expect(handshake?.supportedBridgeMajor).toBe(1);
  });

  it("submitCommand posts an operation request and resolves on the matching response", async () => {
    const { sent } = installChannel();
    const bridge = createWKWebViewCerebralBridge();

    const promise = bridge.submitCommand({ rawInput: "mode developer", source: "dashboard" });
    const op = sent.find(
      (m) => m.type === "bridge.operation.request" && m.operation === "submitCommand"
    );
    expect((op?.payload as Record<string, unknown>).rawInput).toBe("mode developer");

    reply({
      type: "bridge.operation.response",
      messageId: op?.messageId,
      operation: "submitCommand",
      status: "ok",
      payload: { commandId: "cmd_1", accepted: true }
    });
    await expect(promise).resolves.toEqual({ commandId: "cmd_1", accepted: true });
  });

  it("rejects when the native side returns an operation error", async () => {
    const { sent } = installChannel();
    const bridge = createWKWebViewCerebralBridge();

    const promise = bridge.captureNote({ title: "t", body: "b" });
    const op = sent.find((m) => m.operation === "captureNote");
    reply({
      type: "bridge.operation.response",
      messageId: op?.messageId,
      operation: "captureNote",
      status: "error",
      error: { message: "not wired yet" }
    });
    await expect(promise).rejects.toThrow("not wired yet");
  });

  it("unwraps getRecentActivity from its envelope", async () => {
    const { sent } = installChannel();
    const bridge = createWKWebViewCerebralBridge();

    const promise = bridge.getRecentActivity();
    const op = sent.find((m) => m.operation === "getRecentActivity");
    reply({
      type: "bridge.operation.response",
      messageId: op?.messageId,
      operation: "getRecentActivity",
      status: "ok",
      payload: { recentActivity: { commands: [], toolCalls: [], confirmations: [], modeSessions: [], errors: [] } }
    });
    await expect(promise).resolves.toEqual({
      commands: [],
      toolCalls: [],
      confirmations: [],
      modeSessions: [],
      errors: []
    });
  });

  it("getSettings posts an empty request and resolves the snapshot payload directly", async () => {
    const { sent } = installChannel();
    const bridge = createWKWebViewCerebralBridge();

    const promise = bridge.getSettings();
    const op = sent.find((m) => m.operation === "getSettings");
    expect(op?.type).toBe("bridge.operation.request");
    expect(op?.payload).toEqual({});

    const snapshot = {
      schemaVersion: "1.0.0",
      defaultModeId: "developer",
      confirmAllActions: true,
      appearance: { reducedMotion: true, assistantName: "Aria" },
      knowledge: { rootReference: null },
      workspace: { windowsStoredByMode: true, mainDisplayId: "system-primary" },
      modeColors: { "executive.primary": "#ffd166" }
    };
    reply({
      type: "bridge.operation.response",
      messageId: op?.messageId,
      operation: "getSettings",
      status: "ok",
      payload: snapshot
    });
    await expect(promise).resolves.toEqual(snapshot);
  });

  it("dispatches events to subscribers and stops after unsubscribe", () => {
    installChannel();
    const bridge = createWKWebViewCerebralBridge();
    const events: BridgeEvent[] = [];
    const unsubscribe = bridge.subscribe((e) => events.push(e));

    reply({
      type: "confirmation.changed",
      eventId: "brevt_00000001",
      schemaVersion: "1.0.0",
      timestamp: "2026-07-02T00:00:00.000Z",
      payload: { confirmation: null }
    });
    expect(events).toHaveLength(1);
    expect(events[0].type).toBe("confirmation.changed");

    unsubscribe();
    reply({
      type: "command.lifecycle.transition",
      eventId: "brevt_00000002",
      schemaVersion: "1.0.0",
      timestamp: "2026-07-02T00:00:01.000Z",
      payload: { currentStatus: "running" }
    });
    expect(events).toHaveLength(1);
  });

  it("passes workflow progress and display topology events through the type gate", () => {
    installChannel();
    const bridge = createWKWebViewCerebralBridge();
    const events: BridgeEvent[] = [];
    bridge.subscribe((e) => events.push(e));

    reply({
      type: "workflow.action.progress",
      eventId: "brevt_00000003",
      schemaVersion: "1.0.0",
      timestamp: "2026-07-06T00:00:00.000Z",
      payload: { workflowId: "open-developer-layout", actionId: "open-editor", status: "running" }
    });
    reply({
      type: "display.topology.changed",
      eventId: "brevt_00000004",
      schemaVersion: "1.0.0",
      timestamp: "2026-07-06T00:00:01.000Z",
      payload: { displays: [], primaryDisplayId: null }
    });
    // Regression: settings.changed must pass the gate so the dashboard re-syncs the
    // assistant name / mode colors live after a save in the separate settings window.
    reply({
      type: "settings.changed",
      eventId: "brevt_00000005",
      schemaVersion: "1.0.0",
      timestamp: "2026-07-10T00:00:00.000Z",
      payload: { settings: {} }
    });

    expect(events.map((e) => e.type)).toEqual([
      "workflow.action.progress",
      "display.topology.changed",
      "settings.changed"
    ]);
  });

  it("getBootstrapState returns the injected bootstrap without a round-trip", async () => {
    installChannel();
    win.__cerebralBootstrap = { mode: "Executive", modes: [] };
    const bridge = createWKWebViewCerebralBridge();
    await expect(bridge.getBootstrapState()).resolves.toEqual({ mode: "Executive", modes: [] });
  });
});
