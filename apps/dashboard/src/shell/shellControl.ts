/**
 * The private `shellControl` script-message channel (NIC-76): web → native shell
 * actions that are Mac-only window/app concerns, deliberately kept off the
 * versioned bridge (opening the native settings window, rebinding the palette
 * hotkey). In a plain browser there is no channel and `postShellControl`
 * returns false so callers can fall back to their web-only behavior.
 */
interface ShellControlWindow extends Window {
  webkit?: { messageHandlers?: { shellControl?: { postMessage(message: unknown): void } } };
}

export function isShellControlAvailable(): boolean {
  if (typeof window === "undefined") {
    return false;
  }
  return Boolean((window as ShellControlWindow).webkit?.messageHandlers?.shellControl);
}

/** Post one shell-control action; returns false when no native channel exists. */
export function postShellControl(action: string, payload: Record<string, unknown> = {}): boolean {
  const handler = (window as ShellControlWindow).webkit?.messageHandlers?.shellControl;
  if (!handler) {
    return false;
  }
  handler.postMessage({ action, ...payload });
  return true;
}
