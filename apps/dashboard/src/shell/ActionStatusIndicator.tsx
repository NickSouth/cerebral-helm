import { useActionStatus } from "../state/ActionStatusProvider";
import { useDashboardState } from "../state/DashboardStateProvider";
import { humanizeId } from "./labels";

/** A small X mark shown beside an error announcement (color comes from the parent's error tint). */
function ErrorGlyph() {
  return (
    <svg
      viewBox="0 0 24 24"
      width="12"
      height="12"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.2"
      strokeLinecap="round"
      aria-hidden="true"
      focusable="false"
    >
      <path d="M6 6l12 12M18 6L6 18" />
    </svg>
  );
}

/**
 * The single execution-feedback surface (NIC-124), pinned to the shell's top-left header cell.
 * It shows, in priority order: a transient announcement pushed via `announce` (an action's honest
 * result or failure — errors render red with an X), otherwise the live per-step progress of an
 * executing quick action from `activeWorkflowRun`. A persistent `aria-live` region announces each
 * change to assistive tech; it is empty (and visually collapsed) when idle. It intentionally does
 * NOT use `role="status"` — the degraded-mode banner owns that single status role — but aria-live
 * gives the same polite-announcement behavior.
 */
export function ActionStatusIndicator() {
  const { message } = useActionStatus();
  const { activeWorkflowRun } = useDashboardState();

  let text: string | null = null;
  let severity: "info" | "error" = "info";
  if (message) {
    text = message.text;
    severity = message.severity;
  } else if (activeWorkflowRun) {
    const run = activeWorkflowRun;
    text = `${humanizeId(run.workflowId)}: step ${run.index} of ${run.total} — ${humanizeId(
      run.actionId
    )} (${run.status})`;
  }

  return (
    <div className="action-status" data-severity={text ? severity : undefined}>
      <p className="action-status__text" aria-live="polite" aria-atomic="true">
        {text && severity === "error" ? (
          <span className="action-status__icon" aria-hidden="true">
            <ErrorGlyph />
          </span>
        ) : null}
        {text}
      </p>
    </div>
  );
}
