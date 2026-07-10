import { resolveQuickAction, type QuickActionDeps } from "./quickActionHandlers";
import type { CerebralBridge, CommandReceipt } from "../bridge/cerebralBridge";

/** NIC-85: workflow-backed quick actions dispatch `run <workflowId>` through the
 *  command bus; a rejected dispatch is announced honestly, never fabricated. */

function makeDeps(receipt: CommandReceipt) {
  const submissions: string[] = [];
  const announced: string[] = [];
  const bridge = {
    submitCommand(input: { rawInput: string; source: string }) {
      submissions.push(input.rawInput);
      return Promise.resolve(receipt);
    }
  } as unknown as CerebralBridge;
  const deps: QuickActionDeps = {
    bridge,
    announce: (text) => {
      announced.push(text);
    }
  };
  return { deps, submissions, announced };
}

async function flushMicrotasks() {
  await Promise.resolve();
  await Promise.resolve();
}

describe("resolveQuickAction (workflow targets)", () => {
  it("dispatches `run <workflowId>` for a workflow-backed wired action", async () => {
    const { deps, submissions, announced } = makeDeps({
      commandId: "cmd_000000000000000000000001",
      accepted: true
    });
    const activate = resolveQuickAction("open-developer-layout", deps);
    expect(activate).not.toBeNull();

    activate?.();
    await flushMicrotasks();
    expect(submissions).toEqual(["run open-developer-layout"]);
    // An accepted dispatch is silent — progress arrives via events, not fabricated text.
    expect(announced).toEqual([]);
  });

  it("announces a rejected dispatch honestly", async () => {
    const { deps, submissions, announced } = makeDeps({ commandId: "", accepted: false });
    resolveQuickAction("open-school-layout", deps)?.();
    await flushMicrotasks();
    expect(submissions).toEqual(["run open-school-layout"]);
    expect(announced).toHaveLength(1);
    expect(announced[0]).toMatch(/couldn't run open-school-layout/);
  });

  it("leaves unwired ids as placeholders and keeps handler-backed actions wired", () => {
    const { deps } = makeDeps({ commandId: "cmd_x", accepted: true });
    expect(resolveQuickAction("start-focus-block", deps)).toBeNull();
    expect(resolveQuickAction("capture-note", deps)).not.toBeNull();
  });
});
