import { act, renderHook, waitFor } from "@testing-library/react";
import { createElement, type ReactNode } from "react";
import { BridgeProvider } from "../state/BridgeProvider";
import { useReportComposition } from "./useReportComposition";
import type { CerebralBridge, ComposeReportResult } from "../bridge/cerebralBridge";

/**
 * NIC-228: composing once per open, and never once per render.
 *
 * The failure this file exists to catch is the expensive one. `useReportDocument` composes on
 * **every** render from a fresh `new Date()`, and a composition reaches a calendar, an inbox,
 * Linear and a model that takes around nine seconds — so a hook that fired per render would
 * multiply all of it silently, and the symptom would be a slow machine rather than a wrong report.
 */

const composed: ComposeReportResult = {
  state: "ready",
  attempts: 1,
  totalMs: 900,
  document: {
    schemaVersion: "1.0.0",
    reportId: "daily-brief",
    blocks: [{ blockKind: "line", text: "Your calendar is clear." }]
  }
};

function harness(composeReport: (reportId: string) => Promise<ComposeReportResult>) {
  const calls: string[] = [];
  const bridge = {
    composeReport: (reportId: string) => {
      calls.push(reportId);
      return composeReport(reportId);
    }
  } as unknown as CerebralBridge;

  const wrapper = ({ children }: { children: ReactNode }) =>
    createElement(BridgeProvider, { bridge, children });

  return { calls, wrapper };
}

describe("useReportComposition", () => {
  it("composes once per open, not once per render", async () => {
    const { calls, wrapper } = harness(() => Promise.resolve(composed));
    const { result, rerender } = renderHook(
      ({ enabled }) => useReportComposition("daily-brief", enabled),
      { wrapper, initialProps: { enabled: true } }
    );

    await waitFor(() => expect(result.current.status).toBe("ready"));
    rerender({ enabled: true });
    rerender({ enabled: true });

    expect(calls).toEqual(["daily-brief"]);
  });

  it("does not compose for a report that is not open", () => {
    const { calls, wrapper } = harness(() => Promise.resolve(composed));
    renderHook(() => useReportComposition("daily-brief", false), { wrapper });

    expect(calls).toHaveLength(0);
  });

  it("composes again when the report is reopened", async () => {
    // A brief is about right now. The one from an hour ago is worse than the wait.
    const { calls, wrapper } = harness(() => Promise.resolve(composed));
    const { result, rerender } = renderHook(
      ({ enabled }) => useReportComposition("daily-brief", enabled),
      { wrapper, initialProps: { enabled: true } }
    );

    await waitFor(() => expect(result.current.status).toBe("ready"));
    rerender({ enabled: false });
    expect(result.current.status).toBe("idle");
    rerender({ enabled: true });

    await waitFor(() => expect(calls).toHaveLength(2));
  });

  it("moves its generation once per composition, not once per block", async () => {
    // The report region keys its reveal on this. Keying on block count instead would blank the
    // header a reader is already looking at the moment the body arrived.
    const { wrapper } = harness(() => Promise.resolve(composed));
    const { result } = renderHook(() => useReportComposition("daily-brief", true), { wrapper });

    const started = result.current.generation;
    await waitFor(() => expect(result.current.status).toBe("ready"));
    // Composing → ready is the same composition, so the generation must not move again.
    expect(result.current.generation).toBe(started);

    await act(async () => {
      result.current.refresh();
    });
    expect(result.current.generation).toBe(started + 1);
  });

  it("carries the host's reason rather than inventing one", async () => {
    const { wrapper } = harness(() =>
      Promise.resolve({ state: "unavailable", reason: "Ollama isn’t running." } as ComposeReportResult)
    );
    const { result } = renderHook(() => useReportComposition("daily-brief", true), { wrapper });

    await waitFor(() => expect(result.current.status).toBe("unavailable"));
    expect(result.current.reason).toBe("Ollama isn’t running.");
    // No document is not an empty document: the region shows why rather than a blank body.
    expect(result.current.document).toBeNull();
  });

  it("survives the bridge itself failing", async () => {
    const { wrapper } = harness(() => Promise.reject(new Error("transport gone")));
    const { result } = renderHook(() => useReportComposition("daily-brief", true), { wrapper });

    await waitFor(() => expect(result.current.status).toBe("unavailable"));
    expect(result.current.reason).toBeTruthy();
  });

  it("ignores a composition that resolves after it was superseded", async () => {
    // A nine-second round trip has ample time to be overtaken by a refresh or by the reader closing
    // the report. Without the guard, a stale answer would overwrite a fresher one.
    let settleFirst: (value: ComposeReportResult) => void = () => {};
    let call = 0;
    const { wrapper } = harness(() => {
      call += 1;
      if (call === 1) {
        return new Promise<ComposeReportResult>((resolve) => {
          settleFirst = resolve;
        });
      }
      return Promise.resolve(composed);
    });

    const { result } = renderHook(() => useReportComposition("daily-brief", true), { wrapper });
    await act(async () => {
      result.current.refresh();
    });
    await waitFor(() => expect(result.current.status).toBe("ready"));

    // The first composition lands late, carrying a different answer. It must be discarded.
    await act(async () => {
      settleFirst({ state: "unavailable", reason: "stale" });
    });
    expect(result.current.status).toBe("ready");
    expect(result.current.reason).toBeNull();
  });
});
