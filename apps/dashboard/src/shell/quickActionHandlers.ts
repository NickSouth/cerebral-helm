import type { CerebralBridge } from "../bridge/cerebralBridge";
import type { ActionStatusSeverity } from "../state/ActionStatusProvider";
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
 * bridge actually returned via `announce` (the top-left status line — NIC-124). Nothing is
 * fabricated as successful.
 */
export interface QuickActionDeps {
  readonly bridge: CerebralBridge;
  /** Surface a transient, honest result in the top-left status line (NIC-124). */
  announce(text: string, severity?: ActionStatusSeverity): void;
}

type HandlerName = keyof typeof HANDLERS;

const HANDLERS = {
  async captureNote({ bridge, announce }: QuickActionDeps): Promise<void> {
    // No content-entry affordance exists pre-Mac, so this captures a labelled quick note and
    // reports the real returned id. The status text is explicit that capture is a mock
    // until the knowledge system lands — honest-unavailable, never fake-rich.
    const result = await bridge.captureNote({
      title: "Quick note",
      body: "",
      kind: "quick-capture"
    });
    announce(
      `Captured a quick note (${result.noteId}). Quick capture is a mock pre-Mac — note content entry arrives with the knowledge system.`
    );
  }
} satisfies Record<string, (deps: QuickActionDeps) => Promise<void>>;

const WIRED_ACTIONS = wiringManifest.wiredActions as Readonly<
  Record<string, { readonly handler?: string; readonly workflow?: string }>
>;

/**
 * Dispatch a workflow-backed quick action: `run <workflowId>` through the same command
 * bus as the palette (FR-CMD-01). The runtime plans the workflow, gates its aggregate
 * risk, and executes step by step; live progress arrives as `workflow.action.progress`
 * events, so this only surfaces a rejected dispatch — never a fabricated result.
 */
function runWorkflow(workflowId: string, { bridge, announce }: QuickActionDeps): void {
  void bridge
    .submitCommand({ rawInput: `run ${workflowId}`, source: "dashboard" })
    .then((receipt) => {
      if (!receipt.accepted) {
        announce(`I couldn't run ${workflowId} — it isn't a configured workflow.`, "error");
      }
    })
    .catch(() => {
      announce(`Running ${workflowId} failed — the bridge did not accept the command.`, "error");
    });
}

/**
 * Enter layout mode for a mode (NIC-142). A mode's `open-<mode>-layout` action does
 * two things at once — open + arrange the layout's windows AND activate the bottom-bar
 * layout section — so it goes through the dedicated `openLayout` op (which starts the
 * session and runs the open workflow) rather than a bare `run <workflow>`.
 */
function openLayout(modeId: string, { bridge, announce }: QuickActionDeps): void {
  void bridge
    .openLayout({ modeId })
    .then((result) => {
      if (!result.accepted) {
        announce(`${modeId} has no layout to open.`, "error");
      }
    })
    .catch(() => {
      announce(`Opening the ${modeId} layout failed — the bridge did not accept it.`, "error");
    });
}

/** Matches a mode's layout-open action id, capturing the mode id. */
const LAYOUT_ACTION = /^open-([a-z][a-z0-9-]*)-layout$/;

/**
 * Resolve a quick-action id to its click handler, or `null` if the id is a placeholder. A wired
 * action names exactly one target: a `handler` implemented above, or a `workflow` run through
 * the command bus. A wired handler with no implementation here throws — the wiring gate makes
 * that unreachable in a valid build, so the throw is a developer-error guard, not a runtime path.
 */
export function resolveQuickAction(actionId: string, deps: QuickActionDeps): (() => void) | null {
  // A layout-open action enters layout mode through the dedicated openLayout op
  // (session + windows), not a bare workflow run — even though the manifest wires it
  // to the same synthesized workflow for the resolution gate.
  const layoutMatch = LAYOUT_ACTION.exec(actionId);
  if (layoutMatch) {
    const modeId = layoutMatch[1];
    return () => {
      openLayout(modeId, deps);
    };
  }
  const target = WIRED_ACTIONS[actionId];
  if (target?.workflow) {
    const workflowId = target.workflow;
    return () => {
      runWorkflow(workflowId, deps);
    };
  }
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
