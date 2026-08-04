import type { CerebralBridge } from "../bridge/cerebralBridge";
import type { ActionStatusSeverity } from "../state/ActionStatusProvider";
import { quickActionEntry } from "./quickActionRegistry";
import { submitGoogleSearch } from "./googleSearch";

/**
 * Quick-action dispatch. The 4 + 4 slots render the active mode's `quickActions` ids; each id
 * resolves through the dispatch registry (`quickActions.registry.json`), which names the action's
 * `target` once it is built — a coded `handler` below, a `workflow` run through the command bus, or
 * a mode `layout`. An entry with no target is planned, not built, and stays a labelled placeholder.
 * The `validateQuickActionRegistry` gate (scripts/validate-config.mjs) guarantees every declared
 * target resolves, so a missing implementation here is a typed lookup miss, never a silent no-op.
 *
 * Results stay honest: a handler dispatches the real bridge op and surfaces only what the
 * bridge actually returned via `announce` (the top-left status line — NIC-124). Nothing is
 * fabricated as successful.
 */
export interface QuickActionDeps {
  readonly bridge: CerebralBridge;
  /** Surface a transient, honest result in the top-left status line (NIC-124). */
  announce(text: string, severity?: ActionStatusSeverity): void;
  /**
   * Open a Report in the centre panel's Report region. Optional: a caller with no report surface
   * (a test, a future headless dispatcher) leaves a `report` action unresolved rather than
   * pretending it ran.
   */
  openReport?(reportId: string): void;
  /** Open an Input's form in the centre panel's Input region. Optional for the same reason. */
  openInput?(actionId: string): void;
}

type HandlerName = keyof typeof HANDLERS;

/**
 * Params supplied by an action reference inside a report. **Untrusted by construction**: once a
 * model composes the document, these are model-chosen values. A handler must validate what it
 * reads and pass it only as data — never as a destination. That is why `searchTheWeb` hands the
 * query to the `google.search` tool, which builds the google.com URL host-side.
 */
export type QuickActionParams = Readonly<Record<string, unknown>>;

function readString(params: QuickActionParams | undefined, key: string): string | null {
  const value = params?.[key];
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

const HANDLERS = {
  /**
   * Look something up on the web. Reachable only as an action reference from a report — it holds
   * no quick-action slot — so its query always arrives as a param.
   */
  async searchTheWeb({ bridge, announce }: QuickActionDeps, params?: QuickActionParams): Promise<void> {
    const query = readString(params, "query");
    if (!query) {
      announce("That link had nothing to search for.", "error");
      return;
    }
    const receipt = await submitGoogleSearch(bridge, query);
    if (!receipt.accepted) {
      announce(`I couldn't search for “${query}” — the command wasn't accepted.`, "error");
    }
  }
} satisfies Record<string, (deps: QuickActionDeps, params?: QuickActionParams) => Promise<void>>;

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

/**
 * Resolve a quick-action id to its click handler, or `null` if the action is planned but not
 * built (no registry target) — the slot then renders as a labelled placeholder. A registered
 * handler target with no implementation here throws: the registry gate makes that unreachable
 * in a valid build, so the throw is a developer-error guard, not a runtime path.
 */
export function resolveQuickAction(
  actionId: string,
  deps: QuickActionDeps,
  params?: QuickActionParams
): (() => void) | null {
  const target = quickActionEntry(actionId)?.target;
  if (!target) {
    return null;
  }
  switch (target.kind) {
    // A layout action enters layout mode through the dedicated openLayout op (session +
    // windows), not a bare `run <workflow>` of the same synthesized workflow.
    case "layout":
      return () => {
        openLayout(target.mode, deps);
      };
    case "workflow":
      return () => {
        runWorkflow(target.workflow, deps);
      };
    // A Report renders in the dashboard, so it never touches the command bus — the document is
    // composed from providers already streaming into dashboard state.
    case "report": {
      const openReport = deps.openReport;
      return openReport ? () => openReport(actionId) : null;
    }
    // An Input renders its form in the dashboard; the form's own submit performs the action.
    case "input": {
      const openInput = deps.openInput;
      return openInput ? () => openInput(actionId) : null;
    }
    case "handler": {
      const handler = HANDLERS[target.handler as HandlerName];
      if (!handler) {
        throw new Error(`Quick action "${actionId}" targets unknown handler "${target.handler}".`);
      }
      return () => {
        void handler(deps, params);
      };
    }
  }
}
