import { useActiveMode } from "./useActiveMode";
import { quickActionLabel, quickActionTone } from "./quickActionRegistry";
import { resolveQuickAction } from "./quickActionHandlers";
import { useBridge } from "../state/BridgeProvider";
import { useActionStatus } from "../state/ActionStatusProvider";
import { useDashboardState } from "../state/DashboardStateProvider";
import { useUiPosture } from "../state/useUiPosture";
import { useReports } from "../state/ReportProvider";
import { useInputs } from "../state/InputProvider";

/**
 * The 4 + 4 quick-action geometry (§5.7): a row of bars over a row of boxes, rendered from the
 * active mode's `quickActions`. Labels come from the dispatch registry, which also decides what a
 * slot does; an action with a registry target is live, one without stays labelled but greyed
 * ("coming soon") until it is built.
 *
 * **An unconfigured (null) slot is omitted, not rendered as an "Add action" placeholder**
 * (docs/quick-actions/PLAN.md): a mode holding slots for the LLM era should look deliberately
 * shorter, not unfinished. Each slot keeps its quarter-row width, so the survivors re-centre
 * within their own row and the bar/box split is preserved.
 */
function QuickActionSlot({
  action,
  variant,
  onActivate
}: {
  action: string;
  variant: "bar" | "box";
  onActivate: (() => void) | null;
}) {
  const wired = onActivate !== null;
  // Tone applies only to a live slot: a greyed placeholder painted red would read as a warning
  // about something that cannot even be pressed.
  const tone = wired ? quickActionTone(action) : null;
  return (
    <button
      type="button"
      className={`quick-action quick-action--${variant}${wired ? " quick-action--wired" : ""}${
        tone ? ` quick-action--${tone}` : ""
      }`}
      disabled={!wired}
      aria-disabled={!wired}
      title={wired ? undefined : "Coming soon"}
      onClick={onActivate ?? undefined}
    >
      {quickActionLabel(action)}
    </button>
  );
}

/** Narrows a slot row to its configured actions, dropping the unconfigured (null) slots. */
function configured(slots: readonly (string | null)[]): string[] {
  return slots.filter((slot): slot is string => slot !== null);
}

export function QuickActions() {
  const { quickActions } = useActiveMode();
  const bridge = useBridge();
  const { announce } = useActionStatus();
  const { readOnly } = useUiPosture();
  const { activeWorkflowRun } = useDashboardState();
  const { openReport } = useReports();
  const { openInput } = useInputs();
  const deps = { bridge, announce, openReport, openInput };

  // Read-only recovery exposes no mutating controls: every action stays disabled (NIC-64 AC).
  // While a workflow is executing, its actions are also disabled — one run at a time.
  const running = activeWorkflowRun != null;
  const resolve = (action: string) =>
    !readOnly && !running ? resolveQuickAction(action, deps) : null;
  const bars = configured(quickActions.slice(0, 4));
  const boxes = configured(quickActions.slice(4, 8));

  return (
    <div className="quick-actions" role="group" aria-label="Quick actions">
      <div className="quick-actions__bars">
        {bars.map((action) => (
          <QuickActionSlot
            key={action}
            action={action}
            variant="bar"
            onActivate={resolve(action)}
          />
        ))}
      </div>
      <div className="quick-actions__boxes">
        {boxes.map((action) => (
          <QuickActionSlot
            key={action}
            action={action}
            variant="box"
            onActivate={resolve(action)}
          />
        ))}
      </div>
    </div>
  );
}
