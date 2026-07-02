import { createContext, useContext, useSyncExternalStore, type ReactNode } from "react";
import type { DashboardMode } from "../bridge/types";
import type { DashboardState, DashboardStore } from "./dashboardState";

const DashboardStateContext = createContext<DashboardState | null>(null);

/**
 * Holds the current dashboard state behind the store seam. Subscribes to the store via
 * useSyncExternalStore so bridge-driven state changes (NIC-52 B2) re-render consumers;
 * useDashboardState does not change.
 */
export function DashboardStateProvider({
  store,
  children
}: {
  store: DashboardStore;
  children: ReactNode;
}) {
  const state = useSyncExternalStore(store.subscribe, store.getState);

  return <DashboardStateContext.Provider value={state}>{children}</DashboardStateContext.Provider>;
}

export function useDashboardState(): DashboardState {
  const state = useContext(DashboardStateContext);

  if (state === null) {
    throw new Error("useDashboardState must be used within a DashboardStateProvider.");
  }

  return state;
}

export function useDashboardMode(): DashboardMode {
  return useDashboardState().mode;
}
