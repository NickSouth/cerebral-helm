import { act, cleanup, render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { SettingsSnapshotProvider, useSettingsSnapshot } from "./SettingsSnapshotProvider";
import { BridgeProvider } from "../../state/BridgeProvider";
import type {
  BridgeEvent,
  BridgeEventListener,
  CerebralBridge,
  SettingsSnapshot
} from "../../bridge/cerebralBridge";

afterEach(cleanup);

function snapshot(overrides: Partial<SettingsSnapshot> = {}): SettingsSnapshot {
  return {
    schemaVersion: "1.0.0",
    defaultModeId: "executive",
    confirmAllActions: false,
    appearance: { reducedMotion: false, assistantName: "Heimlich" },
    knowledge: { rootReference: null },
    workspace: {
      windowsStoredByMode: false,
      mainDisplayId: "system-primary",
      layoutDisplayId: "system-primary"
    },
    modeColors: {},
    stocks: { tickers: [] },
    calendarModeMap: {},
    ...overrides
  } as SettingsSnapshot;
}

function settingsEvent(payload: Readonly<Record<string, unknown>>): BridgeEvent {
  return {
    eventId: "brevt_test",
    type: "settings.changed",
    schemaVersion: "1.0.0",
    timestamp: "2026-08-05T12:00:00.000Z",
    payload
  };
}

/** A fake bridge exposing only what the provider uses, plus a handle to drive the event stream. */
function fakeBridge(getSettings: () => Promise<SettingsSnapshot>) {
  const listeners = new Set<BridgeEventListener>();
  const unsubscribed = vi.fn();
  const bridge = {
    getSettings,
    subscribe(listener: BridgeEventListener) {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
        unsubscribed();
      };
    }
  } as unknown as CerebralBridge;
  return {
    bridge,
    unsubscribed,
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

/** Renders the two snapshot facts the assertions need: the status and the assistant name. */
function Probe() {
  const { status, snapshot: current } = useSettingsSnapshot();
  return (
    <>
      <span data-testid="status">{status}</span>
      <span data-testid="name">{current?.appearance.assistantName ?? "—"}</span>
      <span data-testid="calendars">{JSON.stringify(current?.calendarModeMap ?? null)}</span>
    </>
  );
}

function renderProvider(bridge: CerebralBridge) {
  return render(
    <BridgeProvider bridge={bridge}>
      <SettingsSnapshotProvider>
        <Probe />
      </SettingsSnapshotProvider>
    </BridgeProvider>
  );
}

describe("SettingsSnapshotProvider", () => {
  it("initializes from the on-demand read", async () => {
    const { bridge } = fakeBridge(async () => snapshot({ appearance: { reducedMotion: false, assistantName: "Read" } }));
    renderProvider(bridge);

    await waitFor(() => expect(screen.getByTestId("status")).toHaveTextContent("ready"));
    expect(screen.getByTestId("name")).toHaveTextContent("Read");
  });

  it("follows settings.changed so a write is reflected without a re-read (NIC-176)", async () => {
    const getSettings = vi.fn(async () => snapshot());
    const harness = fakeBridge(getSettings);
    renderProvider(harness.bridge);
    await waitFor(() => expect(screen.getByTestId("status")).toHaveTextContent("ready"));

    harness.emit(
      settingsEvent({ settings: snapshot({ calendarModeMap: { "cal-work": "developer" } }) })
    );

    // The event alone updates the snapshot — the provider never re-reads.
    expect(screen.getByTestId("calendars")).toHaveTextContent('{"cal-work":"developer"}');
    expect(getSettings).toHaveBeenCalledTimes(1);
  });

  it("ignores a malformed payload rather than clearing a good snapshot", async () => {
    const harness = fakeBridge(async () => snapshot({ appearance: { reducedMotion: false, assistantName: "Kept" } }));
    renderProvider(harness.bridge);
    await waitFor(() => expect(screen.getByTestId("name")).toHaveTextContent("Kept"));

    // No `settings` key, a non-object, and an object that is not a snapshot (no schemaVersion).
    harness.emit(settingsEvent({}));
    harness.emit(settingsEvent({ settings: "nope" }));
    harness.emit(settingsEvent({ settings: null }));
    harness.emit(settingsEvent({ settings: { appearance: { assistantName: "Bogus" } } }));

    expect(screen.getByTestId("status")).toHaveTextContent("ready");
    expect(screen.getByTestId("name")).toHaveTextContent("Kept");
  });

  it("lets a live event supersede an initial read that resolves later", async () => {
    let resolveRead: (value: SettingsSnapshot) => void = () => {};
    const harness = fakeBridge(
      () =>
        new Promise<SettingsSnapshot>((resolve) => {
          resolveRead = resolve;
        })
    );
    renderProvider(harness.bridge);
    expect(screen.getByTestId("status")).toHaveTextContent("loading");

    // A write lands while the read is still in flight.
    harness.emit(
      settingsEvent({ settings: snapshot({ appearance: { reducedMotion: false, assistantName: "Newer" } }) })
    );
    expect(screen.getByTestId("name")).toHaveTextContent("Newer");

    // The slower read carries pre-write values and must not clobber the newer snapshot.
    await act(async () => {
      resolveRead(snapshot({ appearance: { reducedMotion: false, assistantName: "Stale" } }));
    });
    expect(screen.getByTestId("name")).toHaveTextContent("Newer");
  });

  it("keeps a failed read from clobbering a snapshot delivered by an event", async () => {
    let rejectRead: (reason: unknown) => void = () => {};
    const harness = fakeBridge(
      () =>
        new Promise<SettingsSnapshot>((_resolve, reject) => {
          rejectRead = reject;
        })
    );
    renderProvider(harness.bridge);

    harness.emit(
      settingsEvent({ settings: snapshot({ appearance: { reducedMotion: false, assistantName: "Live" } }) })
    );
    await act(async () => {
      rejectRead(new Error("read failed"));
    });

    expect(screen.getByTestId("status")).toHaveTextContent("ready");
    expect(screen.getByTestId("name")).toHaveTextContent("Live");
  });

  it("unsubscribes on unmount", async () => {
    const harness = fakeBridge(async () => snapshot());
    const view = renderProvider(harness.bridge);
    await waitFor(() => expect(screen.getByTestId("status")).toHaveTextContent("ready"));
    expect(harness.listenerCount()).toBe(1);

    view.unmount();
    expect(harness.unsubscribed).toHaveBeenCalledTimes(1);
    expect(harness.listenerCount()).toBe(0);
  });
});
