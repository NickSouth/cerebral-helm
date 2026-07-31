import type { CerebralBridge, CommandReceipt } from "../bridge/cerebralBridge";

/**
 * Open an https web address in the browser (NIC-127) — used for news article links.
 *
 * Goes through the same command bus as every other action — `submitCommand` with the
 * `web <url>` grammar — so the reusable `web.open` tool is planned by the runtime. Being a
 * `local_write`, it opens in one click (no confirmation), exactly like `google <query>`. The
 * adapter validates the scheme (https only) and host, so a malformed or non-https link from feed
 * data is refused rather than opened. The returned receipt only says whether the command was
 * accepted.
 */
export function submitWebOpen(bridge: CerebralBridge, url: string): Promise<CommandReceipt> {
  return bridge.submitCommand({ rawInput: `web ${url}`, source: "dashboard" });
}
