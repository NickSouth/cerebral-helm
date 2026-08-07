import { useActiveMode } from "./useActiveMode";
import { QuickActionGlyph } from "./QuickActionGlyph";
import { quickActionIcon, quickActionLabel, quickActionTone } from "./quickActionRegistry";
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
 *
 * Each slot leads with its registry glyph, muted so the label still leads, and takes the mode
 * accent only while that slot's own surface (a Report or an Input) is open — one consistent
 * open-state indicator across all 32 slots, at no extra cost.
 */
function QuickActionSlot({
  action,
  variant,
  open,
  onActivate
}: {
  action: string;
  variant: "bar" | "box";
  open: boolean;
  onActivate: (() => void) | null;
}) {
  const wired = onActivate !== null;
  // Tone applies only to a live slot: a greyed placeholder painted red would read as a warning
  // about something that cannot even be pressed.
  const tone = wired ? quickActionTone(action) : null;
  const icon = quickActionIcon(action);
  return (
    <button
      type="button"
      className={`quick-action quick-action--${variant}${wired ? " quick-action--wired" : ""}${
        tone ? ` quick-action--${tone}` : ""
      }${open ? " quick-action--open" : ""}`}
      disabled={!wired}
      aria-disabled={!wired}
      // A slot whose surface is open is a toggle: pressing it again closes what it opened.
      aria-pressed={wired ? open : undefined}
      title={wired ? undefined : "Coming soon"}
      onClick={onActivate ?? undefined}
    >
      {/* The bottom row's boxes are the larger control, so they carry a larger, heavier glyph;
          the thin top bars stay lighter so the two rows keep reading as two rows. */}
      {icon ? (
        <QuickActionGlyph
          name={icon}
          size={variant === "bar" ? 17 : 22}
          strokeWidth={variant === "bar" ? 1.6 : 1.85}
        />
      ) : null}
      <span className="quick-action__label">{quickActionLabel(action)}</span>
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
  const { openReport, openReportId } = useReports();
  const { openInput, openInputId } = useInputs();
  const deps = { bridge, announce, openReport, openInput };

  // Read-only recovery exposes no mutating controls: every action stays disabled (NIC-64 AC).
  // While a workflow is executing, its actions are also disabled — one run at a time.
  const running = activeWorkflowRun != null;
  const resolve = (action: string) =>
    !readOnly && !running ? resolveQuickAction(action, deps) : null;
  // Both regions are keyed by the action id that opened them, so one comparison covers Reports and
  // Inputs alike — and a slot that opens neither can never light up.
  const isOpen = (action: string) => openReportId === action || openInputId === action;
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
            open={isOpen(action)}
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
            open={isOpen(action)}
            onActivate={resolve(action)}
          />
        ))}
      </div>
    </div>
  );
}
