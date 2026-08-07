import { createContext, useCallback, useContext, useRef, useState, type ReactNode } from "react";

/** An announcement's weight: `error` renders red with an X icon; `info` reads as quiet muted text. */
export type ActionStatusSeverity = "info" | "error";

export interface ActionStatusMessage {
  readonly text: string;
  readonly severity: ActionStatusSeverity;
}

interface ActionStatusContextValue {
  /** The current transient announcement, or `null` when nothing has been announced (or it dismissed). */
  readonly message: ActionStatusMessage | null;
  /**
   * Surface a transient, honest result of an action in the top-left status line — the only
   * execution-feedback channel now that the Heimlich chat is gone (NIC-124). Latest wins:
   * a new announcement replaces the current one and restarts the auto-dismiss timer. Empty
   * text is ignored so a caller can pass through a value without guarding.
   */
  announce(text: string, severity?: ActionStatusSeverity): void;
  /** Clear the current announcement immediately (e.g. a follow-up action supersedes it). */
  clear(): void;
}

/** How long a transient announcement stays before it auto-dismisses. */
const DISMISS_MS = 6000;

const ActionStatusContext = createContext<ActionStatusContextValue | null>(null);

/**
 * Owns the single transient action-status message rendered top-left (NIC-124). This is the
 * successor to the Heimlich chat's `acknowledge` channel: an action reports only what the bridge
 * actually returned, briefly, then the line clears — nothing is fabricated or persisted. Live
 * per-step workflow progress is NOT held here; it lives in `activeWorkflowRun` on dashboard state
 * and the indicator falls back to it when no transient message is showing.
 */
export function ActionStatusProvider({ children }: { children: ReactNode }) {
  const [message, setMessage] = useState<ActionStatusMessage | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const clear = useCallback(() => {
    if (timer.current !== null) {
      clearTimeout(timer.current);
      timer.current = null;
    }
    setMessage(null);
  }, []);

  const announce = useCallback((text: string, severity: ActionStatusSeverity = "info") => {
    const trimmed = text.trim();
    if (!trimmed) {
      return;
    }
    if (timer.current !== null) {
      clearTimeout(timer.current);
    }
    setMessage({ text: trimmed, severity });
    timer.current = setTimeout(() => {
      timer.current = null;
      setMessage(null);
    }, DISMISS_MS);
  }, []);

  return (
    <ActionStatusContext.Provider value={{ message, announce, clear }}>
      {children}
    </ActionStatusContext.Provider>
  );
}

export function useActionStatus(): ActionStatusContextValue {
  const value = useContext(ActionStatusContext);

  if (value === null) {
    throw new Error("useActionStatus must be used within an ActionStatusProvider.");
  }

  return value;
}
