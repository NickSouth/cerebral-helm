import type { CerebralBridge } from "../bridge/cerebralBridge";
import wiringManifest from "./quickActions.manifest.json";

/**
 * D4 wiring for the trivial quick actions. The 4 + 4 quick-action slots render the active
 * mode's `quickActions` ids; an id present in `quickActions.manifest.json` is **wired** (live),
 * any other id is an allowed placeholder ("coming soon"). The manifest names a `handler` per
 * wired action; the implementations below are keyed by that handler name. The
 * `validateQuickActionWiring` gate (scripts/validate-config.mjs) guarantees every wired
 * handler/workflow target resolves, so a missing implementation here is a typed lookup miss,
 * never a silent no-op.
 *
 * Results stay honest: a handler dispatches the real bridge op and surfaces only what the
 * bridge actually returned via `acknowledge`. Nothing is fabricated as successful.
 */
export interface QuickActionDeps {
  readonly bridge: CerebralBridge;
  /** Append a Heimlich-authored acknowledgement to the conversation (no fake user turn). */
  acknowledge(text: string): void;
}

type HandlerName = keyof typeof HANDLERS;

const HANDLERS = {
  async captureNote({ bridge, acknowledge }: QuickActionDeps): Promise<void> {
    // No content-entry affordance exists pre-Mac, so this captures a labelled quick note and
    // reports the real returned id. The acknowledgement is explicit that capture is a mock
    // until the knowledge system lands — honest-unavailable, never fake-rich.
    const result = await bridge.captureNote({
      title: "Quick note",
      body: "",
      kind: "quick-capture"
    });
    acknowledge(
      `Captured a quick note (${result.noteId}). Quick capture is a mock pre-Mac — note content entry arrives with the knowledge system.`
    );
  }
} satisfies Record<string, (deps: QuickActionDeps) => Promise<void>>;

const WIRED_ACTIONS = wiringManifest.wiredActions as Readonly<
  Record<string, { readonly handler?: string }>
>;

/**
 * Resolve a quick-action id to its click handler, or `null` if the id is a placeholder. A wired
 * action whose handler has no implementation here throws — the wiring gate makes that
 * unreachable in a valid build, so the throw is a developer-error guard, not a runtime path.
 */
export function resolveQuickAction(actionId: string, deps: QuickActionDeps): (() => void) | null {
  const target = WIRED_ACTIONS[actionId];
  if (!target?.handler) {
    return null;
  }
  const handler = HANDLERS[target.handler as HandlerName];
  if (!handler) {
    throw new Error(`Quick action "${actionId}" is wired to unknown handler "${target.handler}".`);
  }
  return () => {
    void handler(deps);
  };
}
