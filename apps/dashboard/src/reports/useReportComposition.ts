import { useCallback, useEffect, useRef, useState } from "react";
import { useBridge } from "../state/BridgeProvider";
import type { ReportDocument } from "./reportDocument";

/** Where one composition has got to. */
export type ReportCompositionStatus = "idle" | "composing" | "ready" | "unavailable";

export interface ReportComposition {
  readonly status: ReportCompositionStatus;
  /** The model's document — its blocks and the envelope the host wrapped them in. */
  readonly document: ReportDocument | null;
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
  const [document, setDocument] = useState<ReportDocument | null>(null);
  const [reason, setReason] = useState<string | null>(null);
  const [generation, setGeneration] = useState(0);
  const started = useRef(false);
  // Guards against a composition that resolves after the reader closed the report, or after a
  // refresh superseded it: a nine-second round trip has plenty of time to be overtaken.
  const run = useRef(0);

  const compose = useCallback(() => {
    run.current += 1;
    const ticket = run.current;
    setStatus("composing");
    setReason(null);
    setGeneration((value) => value + 1);

    void bridge
      .composeReport(reportId)
      .then((result) => {
        if (ticket !== run.current) {
          return;
        }
        if (result.state === "ready" && result.document) {
          setDocument(result.document);
          setStatus("ready");
          return;
        }
        // No document is not an empty document. The region shows why rather than a blank body.
        setDocument(null);
        setReason(result.reason ?? "The brief couldn’t be written just now.");
        setStatus("unavailable");
      })
      .catch(() => {
        if (ticket !== run.current) {
          return;
        }
        // The bridge itself failed — a different thing from the model failing, and not something
        // the reader can act on differently, so it reads the same honest way.
        setDocument(null);
        setReason("The brief couldn’t be written just now.");
        setStatus("unavailable");
      });
  }, [bridge, reportId]);

  useEffect(() => {
    if (!enabled) {
      // Reset so closing and reopening composes again. A brief is about right now, and the one from
      // an hour ago is worse than the wait.
      started.current = false;
      run.current += 1;
      setStatus("idle");
      setDocument(null);
      setReason(null);
      return;
    }
    if (started.current) {
      return;
    }
    started.current = true;
    compose();
  }, [enabled, compose]);

  return { status, document, reason, generation, refresh: compose };
}
