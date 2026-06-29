import { createContext, useContext, useState, type ReactNode } from "react";
import type { DashboardMode } from "../bridge/types";
import type { DashboardState, DashboardStore } from "./dashboardState";

const DashboardStateContext = createContext<DashboardState | null>(null);

/**
 * Holds the current dashboard state behind the store seam. Seeded once from the store;
 * NIC-52 replaces the static seed with bridge-backed, event-driven state plus
 * subscription, and consumers (useDashboardState) do not change.
 */
export function DashboardStateProvider({
  store,
  children
}: {
  store: DashboardStore;
  children: ReactNode;
}) {
  const [state] = useState(() => store.getState());

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
