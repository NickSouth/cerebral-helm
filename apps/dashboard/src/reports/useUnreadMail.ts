import { useCallback, useEffect, useRef, useState } from "react";
import { useBridge } from "../state/BridgeProvider";
import { MAX_LISTED } from "./emailReport";
import type { UnreadMailResult } from "../bridge/cerebralBridge";

/**
 * Reads the unread messages when the email report opens, and again on demand (Gmail integration).
 *
 * **On demand, never on a cadence.** Each message costs a Gmail request, so this fires when the
 * report is opened and when the reader asks for it again — the continuously-sampled count comes
 * from a single label read on a different path entirely.
 *
 * Fetches **once per open** rather than once per render: a re-render firing another round would
 * multiply real network traffic against a personal quota for nothing.
 */
export function useUnreadMail(enabled: boolean): {
  result: UnreadMailResult | null;
  loading: boolean;
  refresh: () => void;
} {
  const bridge = useBridge();
  const [result, setResult] = useState<UnreadMailResult | null>(null);
  const [loading, setLoading] = useState(false);
  const started = useRef(false);

  const refresh = useCallback(() => {
    setLoading(true);
    void bridge
      .listUnreadMail(MAX_LISTED)
      .then(setResult)
      // A failed read reports itself rather than leaving the last list showing: mail that has
      // moved on is worse than an honest "couldn't read it".
      .catch(() =>
        setResult({ state: "unavailable", messages: [], reason: "Your inbox couldn’t be read right now." })
      )
      .finally(() => setLoading(false));
  }, [bridge]);

  useEffect(() => {
    if (!enabled) {
      // Reset, so closing and reopening re-reads — an inbox is exactly the kind of thing that
      // changes while you are looking away.
      started.current = false;
      return;
    }
    if (started.current) {
      return;
    }
    started.current = true;
    refresh();
  }, [enabled, refresh]);

  return { result, loading, refresh };
}
