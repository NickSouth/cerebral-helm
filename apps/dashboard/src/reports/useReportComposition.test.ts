import { act, renderHook, waitFor } from "@testing-library/react";
import { createElement, type ReactNode } from "react";
import { BridgeProvider } from "../state/BridgeProvider";
import { useReportComposition } from "./useReportComposition";
import type {
  BridgeEvent,
  BridgeEventListener,
  CerebralBridge,
  ComposeReportResult
} from "../bridge/cerebralBridge";

/**
 * NIC-228 / NIC-253: composing once per open, and watching the blocks arrive.
 *
 * Two failures this pins. The expensive one: `useReportDocument` composes on **every** render from a
 * fresh `new Date()`, and a composition reaches a calendar, an inbox, Linear and a model that takes
 * around nine seconds — so a hook that fired per render would multiply all of it silently, and the
 * symptom would be a slow machine rather than a wrong report.
 *
 * The subtle one: emissions carry EVERY block so far rather than the new ones, so this must replace
 * rather than append. Appending would double every block on the second emission.
 */

function harness(
  composeReport: (reportId: string) => Promise<ComposeReportResult> = () =>
    Promise.resolve({ state: "composing" })
) {
  const calls: string[] = [];
  const listeners = new Set<BridgeEventListener>();

  const bridge = {
    composeReport: (reportId: string) => {
      calls.push(reportId);
      return composeReport(reportId);
    },
    subscribe: (listener: BridgeEventListener) => {
      listeners.add(listener);
      return () => listeners.delete(listener);
    }
  } as unknown as CerebralBridge;

  const emit = (payload: Record<string, unknown>) => {
    const event = {
      eventId: "brevt_test",
      type: "report.composition.changed",
      schemaVersion: "1.0.0",
      timestamp: new Date().toISOString(),
      payload
    } as unknown as BridgeEvent;
    for (const listener of [...listeners]) listener(event);
  };

  const wrapper = ({ children }: { children: ReactNode }) =>
    createElement(BridgeProvider, { bridge, children });

  return { calls, emit, wrapper, listenerCount: () => listeners.size };
}

const ONE = { blockKind: "line", text: "One." } as const;
const TWO = { blockKind: "line", text: "Two." } as const;

describe("useReportComposition", () => {
  it("composes once per open, not once per render", async () => {
    const { calls, wrapper } = harness();
    const { rerender } = renderHook(
      ({ enabled }) => useReportComposition("daily-brief", enabled),
      { wrapper, initialProps: { enabled: true } }
    );

    rerender({ enabled: true });
    rerender({ enabled: true });

    await waitFor(() => expect(calls).toEqual(["daily-brief"]));
  });

  it("does not compose for a report that is not open", () => {
    const { calls, wrapper } = harness();
    renderHook(() => useReportComposition("daily-brief", false), { wrapper });

    expect(calls).toHaveLength(0);
  });

  it("shows blocks as they arrive rather than waiting for the document", async () => {
    const { emit, wrapper } = harness();
    const { result } = renderHook(() => useReportComposition("daily-brief", true), { wrapper });

    act(() => emit({ reportId: "daily-brief", state: "composing", blocks: [ONE], complete: false }));
    expect(result.current.status).toBe("composing");
    expect(result.current.blocks).toHaveLength(1);
    expect(result.current.complete).toBe(false);

    act(() => emit({ reportId: "daily-brief", state: "ready", blocks: [ONE, TWO], complete: true }));
    expect(result.current.status).toBe("ready");
    expect(result.current.blocks).toHaveLength(2);
    expect(result.current.complete).toBe(true);
  });

  it("replaces the set on each emission rather than appending to it", async () => {
    // The host sends every block so far — the same whole-set rule the health-check run follows.
    // Appending would double every block on the second emission, and the reader would watch the
    // brief repeat itself.
    const { emit, wrapper } = harness();
    const { result } = renderHook(() => useReportComposition("daily-brief", true), { wrapper });

    act(() => emit({ reportId: "daily-brief", state: "composing", blocks: [ONE], complete: false }));
    act(() => emit({ reportId: "daily-brief", state: "composing", blocks: [ONE, TWO], complete: false }));

    expect(result.current.blocks.map((block) => block.text)).toEqual(["One.", "Two."]);
  });

  it("ignores another report's composition", async () => {
    const { emit, wrapper } = harness();
    const { result } = renderHook(() => useReportComposition("daily-brief", true), { wrapper });

    act(() => emit({ reportId: "email-report", state: "ready", blocks: [ONE], complete: true }));

    expect(result.current.blocks).toHaveLength(0);
    expect(result.current.status).toBe("composing");
  });

  it("keeps the host's reason and shows no blocks when a composition fails", async () => {
    // Whatever streamed before the failure came from an attempt that did not survive validation:
    // showing it as final would render a document the composer rejected.
    const { emit, wrapper } = harness();
    const { result } = renderHook(() => useReportComposition("daily-brief", true), { wrapper });

    act(() => emit({ reportId: "daily-brief", state: "composing", blocks: [ONE], complete: false }));
    act(() =>
      emit({
        reportId: "daily-brief",
        state: "unavailable",
        blocks: [],
        complete: true,
        reason: "Ollama isn’t running."
      })
    );

    expect(result.current.status).toBe("unavailable");
    expect(result.current.reason).toBe("Ollama isn’t running.");
    expect(result.current.blocks).toHaveLength(0);
  });

  it("reports a host that refused to start at all", async () => {
    // No model configured: nothing will ever stream, so the refusal itself is the answer.
    const { wrapper } = harness(() =>
      Promise.resolve({ state: "unavailable", reason: "No model is configured." })
    );
    const { result } = renderHook(() => useReportComposition("daily-brief", true), { wrapper });

    await waitFor(() => expect(result.current.status).toBe("unavailable"));
    expect(result.current.reason).toBe("No model is configured.");
  });

  it("survives the bridge itself failing", async () => {
    const { wrapper } = harness(() => Promise.reject(new Error("transport gone")));
    const { result } = renderHook(() => useReportComposition("daily-brief", true), { wrapper });

    await waitFor(() => expect(result.current.status).toBe("unavailable"));
    expect(result.current.reason).toBeTruthy();
  });

  it("moves its generation once per composition, not once per block", async () => {
    // The report region keys its reveal on this. Keying on block count instead would blank the
    // header a reader is already looking at every time another block landed.
    const { emit, wrapper } = harness();
    const { result } = renderHook(() => useReportComposition("daily-brief", true), { wrapper });

    const started = result.current.generation;
    act(() => emit({ reportId: "daily-brief", state: "composing", blocks: [ONE], complete: false }));
    act(() => emit({ reportId: "daily-brief", state: "ready", blocks: [ONE, TWO], complete: true }));
    expect(result.current.generation).toBe(started);

    act(() => {
      result.current.refresh();
    });
    expect(result.current.generation).toBe(started + 1);
    // A refresh clears what the last composition wrote: the two are different briefs.
    expect(result.current.blocks).toHaveLength(0);
  });

  it("composes again when the report is reopened, and unsubscribes when it closes", async () => {
    // A brief is about right now. The one from an hour ago is worse than the wait.
    const { calls, wrapper, listenerCount } = harness();
    const { result, rerender } = renderHook(
      ({ enabled }) => useReportComposition("daily-brief", enabled),
      { wrapper, initialProps: { enabled: true } }
    );

    await waitFor(() => expect(calls).toHaveLength(1));
    expect(listenerCount()).toBe(1);

    rerender({ enabled: false });
    expect(result.current.status).toBe("idle");
    // Nothing left listening for a report nobody is reading.
    expect(listenerCount()).toBe(0);

    rerender({ enabled: true });
    await waitFor(() => expect(calls).toHaveLength(2));
  });
});
