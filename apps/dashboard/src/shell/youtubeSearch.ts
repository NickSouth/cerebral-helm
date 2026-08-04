import type { CerebralBridge, CommandReceipt } from "../bridge/cerebralBridge";

/**
 * Open a YouTube search for `query` in the browser (quick actions phase 4).
 *
 * The exact shape of {@link submitGoogleSearch}, through the same command bus — `submitCommand`
 * with the `youtube <query>` grammar — so the `youtube.search` tool is planned by the runtime.
 * Being a `local_write`, it opens in one click with no confirmation, like `google <query>`.
 *
 * A separate verb and a separate tool rather than a `site:` parameter on the Google one: the
 * adapter owns the destination host as a literal constant, which is what keeps `query` pure data.
 * The returned receipt only says whether the command was accepted.
 */
export function submitYouTubeSearch(bridge: CerebralBridge, query: string): Promise<CommandReceipt> {
  return bridge.submitCommand({ rawInput: `youtube ${query}`, source: "dashboard" });
}
