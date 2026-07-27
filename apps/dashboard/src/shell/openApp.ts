import type { CerebralBridge, CommandReceipt } from "../bridge/cerebralBridge";

/**
 * Launch a configured application by its reference id (NIC-133) — e.g. `open spotify`.
 *
 * Goes through the same command bus as the quick-app tiles: `submitCommand` with the `open <id>`
 * grammar, which the runtime resolves to the `app.open` tool. Being `local_write`, it launches in
 * one click (no confirmation). The returned receipt only says whether the command was accepted.
 */
export function submitOpenApp(bridge: CerebralBridge, appId: string): Promise<CommandReceipt> {
  return bridge.submitCommand({ rawInput: `open ${appId}`, source: "dashboard" });
}
