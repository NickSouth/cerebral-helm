import { useActiveMode } from "./useActiveMode";
import { humanizeId } from "./labels";
import { resolveQuickAction } from "./quickActionHandlers";
import { useBridge } from "../state/BridgeProvider";
import { useConversation } from "../state/ConversationProvider";
import { useDashboardState } from "../state/DashboardStateProvider";
import { useUiPosture } from "../state/useUiPosture";

/**
 * The binding 4 + 4 quick-action geometry (§5.7): four bars over four boxes, ALWAYS eight
 * slots, rendered from the active mode's `quickActions`. A slot whose id is wired
 * (`quickActions.manifest.json`) is live and dispatches its handler; every other id stays
 * labelled but greyed and disabled ("coming soon") until individually wired (D4 wires the
 * trivial ones, e.g. `capture-note`). A null config slot renders as a disabled "Add action".
 */
function QuickActionSlot({
  action,
  variant,
  onActivate
}: {
  action: string | null;
  variant: "bar" | "box";
  onActivate: (() => void) | null;
}) {
  const wired = onActivate !== null;
  return (
    <button
      type="button"
      className={`quick-action quick-action--${variant}${wired ? " quick-action--wired" : ""}`}
      disabled={!wired}
      aria-disabled={!wired}
      title={wired ? undefined : "Coming soon"}
      onClick={onActivate ?? undefined}
    >
      {action ? humanizeId(action) : "Add action"}
    </button>
  );
}

export function QuickActions() {
  const { quickActions } = useActiveMode();
  const bridge = useBridge();
  const { acknowledge } = useConversation();
  const { readOnly } = useUiPosture();
  const { activeWorkflowRun } = useDashboardState();
  const deps = { bridge, acknowledge };

  // Read-only recovery exposes no mutating controls: every action stays disabled (NIC-64 AC).
  // While a workflow is executing, its actions are also disabled — one run at a time.
  const running = activeWorkflowRun != null;
  const resolve = (action: string | null) =>
    action && !readOnly && !running ? resolveQuickAction(action, deps) : null;
  const bars = quickActions.slice(0, 4);
  const boxes = quickActions.slice(4, 8);

  return (
    <div className="quick-actions" role="group" aria-label="Quick actions">
      <div className="quick-actions__bars">
        {bars.map((action, index) => (
          <QuickActionSlot
            key={`bar-${index}`}
            action={action}
            variant="bar"
            onActivate={resolve(action)}
          />
        ))}
      </div>
      <div className="quick-actions__boxes">
        {boxes.map((action, index) => (
          <QuickActionSlot
            key={`box-${index}`}
            action={action}
            variant="box"
            onActivate={resolve(action)}
          />
        ))}
      </div>
      {activeWorkflowRun ? (
        <p className="quick-actions__progress" role="status" aria-live="polite">
          {humanizeId(activeWorkflowRun.workflowId)}: step {activeWorkflowRun.index} of{" "}
          {activeWorkflowRun.total} — {humanizeId(activeWorkflowRun.actionId)} (
          {activeWorkflowRun.status})
        </p>
      ) : null}
    </div>
  );
}
