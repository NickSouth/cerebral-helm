import { act, cleanup, render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { useDiscoveredApps } from "./useDiscoveredApps";
import { BridgeProvider } from "../state/BridgeProvider";
import type {
  BridgeEvent,
  BridgeEventListener,
  CerebralBridge,
  DiscoveredApp,
  ListAppsResult
} from "../bridge/cerebralBridge";

afterEach(cleanup);

function appsEvent(): BridgeEvent {
  return {
    eventId: "brevt_apps0001",
    type: "apps.changed",
    schemaVersion: "1.0.0",
    timestamp: "2026-08-05T12:00:00.000Z",
    payload: {}
  };
}

/** A bridge over a scripted sequence of inventories, plus a handle to drive the event stream. */
function fakeBridge(inventories: readonly (readonly DiscoveredApp[])[]) {
  const listeners = new Set<BridgeEventListener>();
  let call = 0;
  const listApps = vi.fn(
    (): Promise<ListAppsResult> => {
      // The last entry repeats, so extra reads are harmless.
      const apps = inventories[Math.min(call, inventories.length - 1)];
      call += 1;
      return Promise.resolve({ apps, truncated: false });
    }
  );
  const bridge = {
    listApps,
    subscribe(listener: BridgeEventListener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    }
  } as unknown as CerebralBridge;
  return {
    bridge,
    listApps,
    listenerCount: () => listeners.size,
    emit(event: BridgeEvent) {
      act(() => {
        for (const listener of listeners) {
          listener(event);
        }
      });
    }
  };
}

function Probe({ enabled = true }: { enabled?: boolean }) {
  const state = useDiscoveredApps(enabled);
  return (
    <>
      <span data-testid="status">{state.status}</span>
      <span data-testid="names">
        {state.status === "ready" ? state.apps.map((app) => app.name).join(",") : ""}
      </span>
    </>
  );
}

function renderHook(bridge: CerebralBridge, enabled = true) {
  return render(
    <BridgeProvider bridge={bridge}>
      <Probe enabled={enabled} />
    </BridgeProvider>
  );
}

const SAFARI: DiscoveredApp = { bundleId: "com.apple.Safari", name: "Safari" };
const STEAM: DiscoveredApp = { bundleId: "com.valvesoftware.steam", name: "Steam" };

describe("useDiscoveredApps", () => {
  it("reads the inventory on mount", async () => {
    const harness = fakeBridge([[SAFARI]]);
    renderHook(harness.bridge);

    await waitFor(() => expect(screen.getByTestId("status")).toHaveTextContent("ready"));
    expect(screen.getByTestId("names")).toHaveTextContent("Safari");
    expect(harness.listApps).toHaveBeenCalledTimes(1);
  });

  it("re-reads on apps.changed so an install appears without reopening (NIC-175)", async () => {
    const harness = fakeBridge([[SAFARI], [SAFARI, STEAM]]);
    renderHook(harness.bridge);
    await waitFor(() => expect(screen.getByTestId("names")).toHaveTextContent("Safari"));

    // The native watcher fires once the Applications folder settles after an install.
    harness.emit(appsEvent());

    await waitFor(() => expect(screen.getByTestId("names")).toHaveTextContent("Safari,Steam"));
    expect(harness.listApps).toHaveBeenCalledTimes(2);
  });

  it("ignores unrelated events rather than re-scanning on every bridge message", async () => {
    const harness = fakeBridge([[SAFARI]]);
    renderHook(harness.bridge);
    await waitFor(() => expect(harness.listApps).toHaveBeenCalledTimes(1));

    // Discovery is a filesystem scan on every call — it must not run on unrelated traffic.
    harness.emit({ ...appsEvent(), type: "system.status.changed" });
    harness.emit({ ...appsEvent(), type: "weather.changed" });

    expect(harness.listApps).toHaveBeenCalledTimes(1);
  });

  it("reports an honest error when discovery fails, and recovers on the next event", async () => {
    const listeners = new Set<BridgeEventListener>();
    let shouldFail = true;
    const bridge = {
      listApps: () =>
        shouldFail
          ? Promise.reject(new Error("no host"))
          : Promise.resolve({ apps: [SAFARI], truncated: false }),
      subscribe(listener: BridgeEventListener) {
        listeners.add(listener);
        return () => listeners.delete(listener);
      }
    } as unknown as CerebralBridge;

    renderHook(bridge);
    await waitFor(() => expect(screen.getByTestId("status")).toHaveTextContent("error"));

    shouldFail = false;
    act(() => {
      for (const listener of listeners) {
        listener(appsEvent());
      }
    });
    await waitFor(() => expect(screen.getByTestId("status")).toHaveTextContent("ready"));
  });

  it("does nothing at all when disabled (no discovery capability)", () => {
    const harness = fakeBridge([[SAFARI]]);
    renderHook(harness.bridge, false);

    expect(harness.listApps).not.toHaveBeenCalled();
    expect(harness.listenerCount()).toBe(0);
    expect(screen.getByTestId("status")).toHaveTextContent("loading");
  });

  it("unsubscribes on unmount", async () => {
    const harness = fakeBridge([[SAFARI]]);
    const view = renderHook(harness.bridge);
    await waitFor(() => expect(harness.listenerCount()).toBe(1));

    view.unmount();
    expect(harness.listenerCount()).toBe(0);
  });
});
