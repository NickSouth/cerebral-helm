import type { CerebralBridge, CommandReceipt } from "../bridge/cerebralBridge";

/**
 * Ask the runtime to open a repository directory in the configured editor (NIC-131).
 *
 * This goes through the same command bus as every other action — `submitCommand` with the
 * `project <path>` grammar — so the `project.open` tool is planned by the runtime and, being
 * a `local_write`, gated on a policy-owned confirmation that arrives as a
 * `confirmation.changed` event. There is no dedicated bridge operation because there is no
 * distinct result to return: the open completes asynchronously through the lifecycle /
 * confirmation event stream, exactly like a quick action's `run <id>`. The returned receipt
 * only says whether the command was accepted for planning.
 */
export function submitOpenProject(
  bridge: CerebralBridge,
  repoPath: string
): Promise<CommandReceipt> {
  return bridge.submitCommand({ rawInput: `project ${repoPath}`, source: "dashboard" });
}
