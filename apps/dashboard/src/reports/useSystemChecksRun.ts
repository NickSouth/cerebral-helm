import { useCallback, useEffect, useRef } from "react";
import { useBridge } from "../state/BridgeProvider";

/**
 * Starts a system-health run when the report opens, and again on demand (quick actions phase 5).
 *
 * **It returns nothing.** The run's results arrive as `system.checks.changed` events and land in
 * dashboard state, so the composer reads them exactly like the weather or the news — one path in,
 * whether a value came from bootstrap or from a producer. A hook that also returned the results
 * would create a second path that could disagree with the first.
 *
 * The run starts **once per open**, not once per render: these checks reach several third parties,
 * and a re-render firing another round would multiply real network traffic for nothing.
 */
export function useSystemChecksRun(enabled: boolean): { rerun: () => void } {
  const bridge = useBridge();
  const started = useRef(false);

  const rerun = useCallback(() => {
    // A failure to START is silent here on purpose: the surface's honest state is whatever the
    // events say, and a run that never began simply leaves the last one showing rather than
    // replacing it with an error about the plumbing.
    void bridge.runSystemChecks().catch(() => undefined);
  }, [bridge]);

  useEffect(() => {
    if (!enabled) {
      // Reset so closing and reopening the report runs the checks again — the answers are exactly
      // the kind that go stale while you are looking away.
      started.current = false;
      return;
    }
    if (started.current) {
      return;
    }
    started.current = true;
    rerun();
  }, [enabled, rerun]);

  return { rerun };
}
