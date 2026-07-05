import { renderHook, act } from "@testing-library/react";
import { usePaletteMode } from "./usePaletteMode";
import type { BridgeEvent, BridgeEventListener } from "../bridge/cerebralBridge";

interface BootstrapWindow {
  __cerebralBootstrap?: { mode?: string };
}

function fakeBridge() {
  let listener: BridgeEventListener | null = null;
  return {
    subscribe(l: BridgeEventListener) {
      listener = l;
      return () => {
        listener = null;
      };
    },
    emit(event: BridgeEvent) {
      listener?.(event);
    }
  };
}

function configChanged(mode: string): BridgeEvent {
  return {
    eventId: "brevt_test",
    type: "config.changed",
    schemaVersion: "1.0.0",
    timestamp: "2026-07-02T00:00:00.000Z",
    payload: { snapshot: { mode } }
  };
}

afterEach(() => {
  delete (window as unknown as BootstrapWindow).__cerebralBootstrap;
});

describe("usePaletteMode (NIC-76 palette mode-sync)", () => {
  it("seeds from the injected bootstrap mode", () => {
    (window as unknown as BootstrapWindow).__cerebralBootstrap = { mode: "entertainment" };
    const { result } = renderHook(() => usePaletteMode(null));
    expect(result.current).toBe("entertainment");
  });

  it("defaults to executive when no bootstrap is injected", () => {
    const { result } = renderHook(() => usePaletteMode(null));
    expect(result.current).toBe("executive");
  });

  it("re-themes on a config.changed mode switch", () => {
    const bridge = fakeBridge();
    const { result } = renderHook(() => usePaletteMode(bridge));
    expect(result.current).toBe("executive");
    act(() => bridge.emit(configChanged("developer")));
    expect(result.current).toBe("developer");
  });

  it("ignores non-mode events", () => {
    const bridge = fakeBridge();
    const { result } = renderHook(() => usePaletteMode(bridge));
    act(() =>
      bridge.emit({
        eventId: "brevt_x",
        type: "command.lifecycle.transition",
        schemaVersion: "1.0.0",
        timestamp: "2026-07-02T00:00:00.000Z",
        payload: {}
      })
    );
    expect(result.current).toBe("executive");
  });
});
