import type { CerebralBridge, CommandReceipt } from "../bridge/cerebralBridge";

/**
 * Open a Google search for `query` in the browser (NIC-134).
 *
 * Goes through the same command bus as every other action — `submitCommand` with the
 * `google <query>` grammar — so the reusable `google.search` tool is planned by the runtime.
 * Being a `local_write`, it opens in one click (no confirmation), exactly like `project <path>`.
 * The adapter builds the google.com URL host-side, so `query` is only ever data, never the
 * destination host. The returned receipt only says whether the command was accepted.
 */
export function submitGoogleSearch(bridge: CerebralBridge, query: string): Promise<CommandReceipt> {
  return bridge.submitCommand({ rawInput: `google ${query}`, source: "dashboard" });
}
