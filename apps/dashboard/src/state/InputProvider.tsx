import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode
} from "react";
import { useDashboardState } from "./DashboardStateProvider";

/**
 * Which Input (or Picker) is open in the centre panel's lower-right region.
 *
 * Separate from the open Report rather than folded into one "centre surface": the two occupy
 * different parts of the panel and legitimately coexist — reading a brief while filling in an
 * event is a normal thing to do. Only one Input at a time, and pressing an Input's own slot
 * again closes it, matching the Report region's toggle.
 */
interface InputContextValue {
  readonly openInputId: string | null;
  openInput(actionId: string): void;
  closeInput(): void;
}

const InputContext = createContext<InputContextValue | null>(null);

/** `handoff` mirrors `ReportProvider`'s: the sidebar opens forms on the dashboard instead of in
 *  its own column. Returning true suppresses the local open. */
export function InputProvider({
  children,
  handoff
}: {
  children: ReactNode;
  handoff?: (actionId: string) => boolean;
}) {
  const [openInputId, setOpenInputId] = useState<string | null>(null);
  const { mode } = useDashboardState();

  const openInput = useCallback(
    (actionId: string) => {
      if (handoff?.(actionId)) {
        return;
      }
      setOpenInputId((current) => (current === actionId ? null : actionId));
    },
    [handoff]
  );
  const closeInput = useCallback(() => setOpenInputId(null), []);

  // A form is opened from a mode's slot and belongs to it, exactly as a Report does. Switching
  // mode also discards whatever was typed — which is the honest behaviour: the alternative is
  // silently carrying a half-written note into a mode that does not offer the action.
  useEffect(() => {
    setOpenInputId(null);
  }, [mode]);

  const value = useMemo(
    () => ({ openInputId, openInput, closeInput }),
    [openInputId, openInput, closeInput]
  );

  return <InputContext.Provider value={value}>{children}</InputContext.Provider>;
}

export function useInputs(): InputContextValue {
  const value = useContext(InputContext);
  if (!value) {
    throw new Error("useInputs must be used within an InputProvider.");
  }
  return value;
}
