import { createContext, useContext, type ReactNode } from "react";
import type { CerebralBridge } from "../bridge/cerebralBridge";

const BridgeContext = createContext<CerebralBridge | null>(null);

/**
 * Provides the CerebralBridge to components that dispatch intent (e.g. the mode switcher
 * calling `applyMode`). Reading state stays on the DashboardStore seam (useDashboardState);
 * this is the write side. Transport-agnostic — the same provider wraps the native bridge.
 */
export function BridgeProvider({
  bridge,
  children
}: {
  bridge: CerebralBridge;
  children: ReactNode;
}) {
  return <BridgeContext.Provider value={bridge}>{children}</BridgeContext.Provider>;
}

export function useBridge(): CerebralBridge {
  const bridge = useContext(BridgeContext);

  if (bridge === null) {
    throw new Error("useBridge must be used within a BridgeProvider.");
  }

  return bridge;
}
