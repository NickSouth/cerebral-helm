/**
 * The private `sidebarControl` script-message channel: web → native window control for the
 * edge sidebar (dismiss, pin, content-height reporting), deliberately kept off the versioned
 * bridge deliberately: which window is on screen is a native-app concern, not part of the
 * versioned contract.
 *
 * In a plain browser preview there is no channel and these are no-ops, so the surface stays
 * fully renderable at `?surface=sidebar` for design work and tests.
 */
interface SidebarControlWindow extends Window {
  webkit?: { messageHandlers?: { sidebarControl?: { postMessage(message: unknown): void } } };
}

export function isSidebarControlAvailable(): boolean {
  if (typeof window === "undefined") {
    return false;
  }
  return Boolean((window as SidebarControlWindow).webkit?.messageHandlers?.sidebarControl);
}

/** Post one sidebar-control action; returns false when no native channel exists. */
export function postSidebarControl(action: string, payload: Record<string, unknown> = {}): boolean {
  if (typeof window === "undefined") {
    return false;
  }
  const handler = (window as SidebarControlWindow).webkit?.messageHandlers?.sidebarControl;
  if (!handler) {
    return false;
  }
  handler.postMessage({ action, ...payload });
  return true;
}
