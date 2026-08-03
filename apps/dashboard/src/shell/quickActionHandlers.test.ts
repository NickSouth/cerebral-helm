import { resolveQuickAction, type QuickActionDeps } from "./quickActionHandlers";
import type { CerebralBridge, CommandReceipt } from "../bridge/cerebralBridge";

/** NIC-85: workflow-backed quick actions dispatch through the command bus; a rejected
 *  dispatch is announced honestly, never fabricated. NIC-142: a mode's
 *  `open-<mode>-layout` action enters layout mode via the dedicated openLayout op —
 *  now because the dispatch registry declares a `layout` target, not because the id
 *  matched a regex. */

function makeDeps(opts: { receipt?: CommandReceipt; openAccepted?: boolean } = {}) {
  const submissions: string[] = [];
  const opened: string[] = [];
  const announced: string[] = [];
  const bridge = {
    submitCommand(input: { rawInput: string; source: string }) {
      submissions.push(input.rawInput);
      return Promise.resolve(opts.receipt ?? { commandId: "cmd_x", accepted: true });
    },
    openLayout(input: { modeId: string }) {
      opened.push(input.modeId);
      return Promise.resolve({ accepted: opts.openAccepted ?? true, modeId: input.modeId });
    }
  } as unknown as CerebralBridge;
  const deps: QuickActionDeps = {
    bridge,
    announce: (text) => {
      announced.push(text);
    }
  };
  return { deps, submissions, opened, announced };
}

async function flushMicrotasks() {
  await Promise.resolve();
  await Promise.resolve();
}

describe("resolveQuickAction (layout targets)", () => {
  it("enters layout mode via openLayout for a mode's open-<mode>-layout action", async () => {
    const { deps, opened, submissions, announced } = makeDeps({ openAccepted: true });
    const activate = resolveQuickAction("open-developer-layout", deps);
    expect(activate).not.toBeNull();

    activate?.();
    await flushMicrotasks();
    // Opens through the dedicated op (session + windows), not a bare `run <workflow>`.
    expect(opened).toEqual(["developer"]);
    expect(submissions).toEqual([]);
    // An accepted open is silent — the bar renders from the layout.session.changed event.
    expect(announced).toEqual([]);
  });

  it("announces a mode with no authored layout honestly", async () => {
    const { deps, opened, announced } = makeDeps({ openAccepted: false });
    resolveQuickAction("open-school-layout", deps)?.();
    await flushMicrotasks();
    expect(opened).toEqual(["school"]);
    expect(announced).toHaveLength(1);
    expect(announced[0]).toMatch(/school has no layout/);
  });

  it("leaves targetless (planned) actions as placeholders and keeps handler-backed actions wired", () => {
    const { deps } = makeDeps();
    // Registered, with no target yet — planned, not built.
    expect(resolveQuickAction("daily-brief", deps)).toBeNull();
    expect(resolveQuickAction("capture-note", deps)).not.toBeNull();
  });

  it("returns null for an id that is not registered at all", () => {
    const { deps } = makeDeps();
    // The config gate makes this unreachable in a valid build; at runtime it must degrade to a
    // disabled slot rather than throwing and taking the shell down.
    expect(resolveQuickAction("no-such-action", deps)).toBeNull();
  });

  it("does not treat an unregistered open-<x>-layout id as a layout action", () => {
    const { deps, opened } = makeDeps();
    // The old regex would have dispatched openLayout("nonsense") for any id of this shape.
    expect(resolveQuickAction("open-nonsense-layout", deps)).toBeNull();
    expect(opened).toEqual([]);
  });
});
