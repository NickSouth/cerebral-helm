import { useCallback, useEffect, useRef, useState } from "react";
import { useBridge } from "../state/BridgeProvider";
import type { ReportBlock } from "./reportDocument";
import type { ReportCompositionPayload } from "../bridge/cerebralBridge";

/** Where one composition has got to. */
export type ReportCompositionStatus = "idle" | "composing" | "ready" | "unavailable";

export interface ReportComposition {
  readonly status: ReportCompositionStatus;
  /**
   * Every block the model has written so far.
   *
   * Replaced wholesale on each emission rather than appended to — the host sends the whole set, so
   * there is no per-block reconciliation here to drift out of step with the composition, and a
   * retry that discarded its first attempt simply sends a shorter set.
   */
  readonly blocks: readonly ReportBlock[];
  /** True once the composition finished, successfully or not. */
  readonly complete: boolean;
  /** Reader-facing prose when the composition could not be produced. Never a decoder's complaint. */
  readonly reason: string | null;
  /**
   * Increments once per composition started.
   *
   * The report region keys its reveal on this rather than on the block count. Block count was a
   * good proxy for "this became a different document" while every composer was synchronous, and it
   * is exactly the wrong one now: a composed brief grows from three blocks to nine partway through,
   * and keying on that would blank the header the reader is already reading and type it again.
   */
  readonly generation: number;
  readonly refresh: () => void;
}

/**
 * Composes one Report with the local model, once per open (NIC-228).
 *
 * Modelled on `useSystemChecksRun` and `useUnreadMail`, and once-per-open for the same reason both
 * of those are: this reaches a model that takes around nine seconds and, before that, a calendar,
 * an inbox and Linear. A re-render firing another round would multiply real work for nothing —
 * and `useReportDocument` composes on **every** render, from a fresh `new Date()`, so "every
 * render" is not a hypothetical here.
 *
 * A failure to compose is not thrown. Every way this fails is a state the region renders, and the
 * host already answers with a reader-facing sentence rather than an error.
 */
export function useReportComposition(reportId: string, enabled: boolean): ReportComposition {
  const bridge = useBridge();
  const [status, setStatus] = useState<ReportCompositionStatus>("idle");
  const [blocks, setBlocks] = useState<readonly ReportBlock[]>([]);
  const [reason, setReason] = useState<string | null>(null);
  const [generation, setGeneration] = useState(0);
  const started = useRef(false);
  // Guards against emissions from a composition the reader has moved on from: closing the report or
  // asking for a refresh supersedes one that is still streaming, and a long composition has ample
  // time to be overtaken.
  const run = useRef(0);

  const compose = useCallback(() => {
    run.current += 1;
    const ticket = run.current;
    setStatus("composing");
    setBlocks([]);
    setReason(null);
    setGeneration((value) => value + 1);

    void bridge
      .composeReport(reportId)
      .then((result) => {
        if (ticket !== run.current || result.state !== "unavailable") {
          return;
        }
        // The host refused to start at all — no model configured. Nothing will stream.
        setReason(result.reason ?? "The brief couldn’t be written just now.");
        setStatus("unavailable");
      })
      .catch(() => {
        if (ticket !== run.current) {
          return;
        }
        setReason("The brief couldn’t be written just now.");
        setStatus("unavailable");
      });
  }, [bridge, reportId]);

  // The blocks arrive as events, exactly as the health-check run's results do. Subscribed for as
  // long as the report is open rather than per composition, so a refresh does not race a resubscribe.
  useEffect(() => {
    if (!enabled) {
      return;
    }
    return bridge.subscribe((event) => {
      if (event.type !== "report.composition.changed") {
        return;
      }
      const payload = event.payload as unknown as ReportCompositionPayload;
      // Another report's composition, or one this hook has superseded.
      if (payload.reportId !== reportId || !Array.isArray(payload.blocks)) {
        return;
      }
      setBlocks(payload.blocks);
      if (!payload.complete) {
        setStatus("composing");
        return;
      }
      if (payload.state === "unavailable") {
        setReason(payload.reason ?? "The brief couldn’t be written just now.");
        setStatus("unavailable");
        return;
      }
      setReason(null);
      setStatus("ready");
    });
  }, [bridge, enabled, reportId]);

  useEffect(() => {
    if (!enabled) {
      // Reset so closing and reopening composes again. A brief is about right now, and the one from
      // an hour ago is worse than the wait.
      started.current = false;
      run.current += 1;
      setStatus("idle");
      setBlocks([]);
      setReason(null);
      return;
    }
    if (started.current) {
      return;
    }
    started.current = true;
    compose();
  }, [enabled, compose]);

  return {
    status,
    blocks,
    complete: status === "ready" || status === "unavailable",
    reason,
    generation,
    refresh: compose
  };
}
