import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import type {
  ConfirmationArgument,
  ConfirmationDisclosure,
  ConfirmationRisk
} from "../bridge/types";
import { useDashboardState } from "../state/DashboardStateProvider";
import { useBridge } from "../state/BridgeProvider";
import { useUiPosture } from "../state/useUiPosture";

/** Risk classes as plain text (policy owns the classification; the UI only labels it, §9). */
const RISK_LABELS: Readonly<Record<ConfirmationRisk, string>> = {
  read_only: "Read only",
  local_write: "Local write",
  external_write: "External write",
  destructive: "Destructive",
  shell: "Shell command",
  financial: "Financial",
  purchase_or_booking: "Purchase or booking"
};

const DATA_LEAVING_LABELS: Readonly<Record<ConfirmationDisclosure["dataLeavingDevice"], string>> = {
  none: "Nothing leaves this device",
  metadata_only: "Metadata only leaves this device",
  content: "Content leaves this device",
  unknown: "Unknown what leaves this device"
};

const REVERSIBILITY_LABELS: Readonly<Record<ConfirmationDisclosure["reversibility"], string>> = {
  reversible: "Reversible",
  partially_reversible: "Partially reversible",
  not_reversible: "Not reversible",
  unknown: "Reversibility unknown"
};

function argumentValue(argument: ConfirmationArgument): string {
  // Sensitive values are never shown verbatim in the disclosure.
  return argument.sensitive ? "•••••• (hidden)" : argument.value;
}

/**
 * The universal, policy-owned confirmation surface (design spec §9, NIC-62). It is **neutral
 * system blue regardless of active mode** (uses the mode-invariant `--ch-confirm-*` tokens,
 * never the mode accent), discloses the exact action in full, and exposes Approve / Review /
 * Cancel. Approve is never the default-focused control — the contract constrains
 * `defaultFocusedChoice` to review/cancel, and that choice receives initial focus. Escape
 * cancels. The decision is submitted to the bridge via `decideConfirmation`; the UI never
 * classifies risk, bypasses policy, or executes the action — and nothing proceeds until the
 * bridge clears the confirmation by event.
 */
function ConfirmationWindow({ confirmation }: { confirmation: ConfirmationDisclosure }) {
  const bridge = useBridge();
  const { readOnly } = useUiPosture();
  const [reviewing, setReviewing] = useState(false);
  const defaultChoiceRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    // Focus the safe default (review/cancel) on mount — never Approve.
    defaultChoiceRef.current?.focus();
  }, []);

  function decide(decision: "approve" | "cancel"): void {
    // Read-only recovery never executes a gated action; approve is inert (NIC-64 AC).
    if (decision === "approve" && readOnly) {
      return;
    }
    void bridge.decideConfirmation({ id: confirmation.id, decision });
  }

  function onKeyDown(event: KeyboardEvent<HTMLDivElement>): void {
    if (event.key === "Escape") {
      event.preventDefault();
      decide("cancel");
    }
  }

  const { choices } = confirmation;
  const defaultIsReview = choices.defaultFocusedChoice === "review";

  return (
    <>
      <div className="confirmation-scrim" />
      {/* A focusable modal dialog that captures Escape to cancel; onKeyDown on the dialog is the
          accessible pattern, so the non-interactive-element-interactions rule is suppressed. */}
      {/* eslint-disable-next-line jsx-a11y/no-noninteractive-element-interactions */}
      <div
        className="confirmation-window"
        role="dialog"
        aria-modal="true"
        aria-label="Confirm action"
        aria-describedby="confirmation-summary"
        onKeyDown={onKeyDown}
      >
        <p className="confirmation-window__eyebrow">
          Confirmation · {RISK_LABELS[confirmation.risk]}
        </p>
        <h2 id="confirmation-summary" className="confirmation-window__summary">
          {confirmation.actionSummary}
        </h2>

        <dl className="confirmation-detail">
          <div className="confirmation-detail__row">
            <dt>Tool</dt>
            <dd>
              {confirmation.tool.id} v{confirmation.tool.version} — {confirmation.tool.purpose}
            </dd>
          </div>
          {confirmation.destination ? (
            <div className="confirmation-detail__row">
              <dt>Destination</dt>
              <dd>{confirmation.destination}</dd>
            </div>
          ) : null}
          {confirmation.accountOrService ? (
            <div className="confirmation-detail__row">
              <dt>Account / service</dt>
              <dd>{confirmation.accountOrService}</dd>
            </div>
          ) : null}
          <div className="confirmation-detail__row">
            <dt>Data</dt>
            <dd>{DATA_LEAVING_LABELS[confirmation.dataLeavingDevice]}</dd>
          </div>
          <div className="confirmation-detail__row">
            <dt>Reversibility</dt>
            <dd>{REVERSIBILITY_LABELS[confirmation.reversibility]}</dd>
          </div>
          <div className="confirmation-detail__row">
            <dt>Why confirm</dt>
            <dd>{confirmation.policyReason}</dd>
          </div>
        </dl>

        {confirmation.arguments.length > 0 ? (
          <div className="confirmation-arguments">
            <p className="confirmation-window__label">Arguments</p>
            <ul>
              {confirmation.arguments.map((argument) => (
                <li key={argument.name}>
                  <span className="confirmation-arguments__name">{argument.name}</span>
                  <span className="confirmation-arguments__value">{argumentValue(argument)}</span>
                </li>
              ))}
            </ul>
          </div>
        ) : null}

        {reviewing ? (
          <dl className="confirmation-detail confirmation-detail--technical">
            <div className="confirmation-detail__row">
              <dt>Command</dt>
              <dd>{confirmation.commandId}</dd>
            </div>
            <div className="confirmation-detail__row">
              <dt>Plan hash</dt>
              <dd className="confirmation-detail__mono">{confirmation.planHash}</dd>
            </div>
          </dl>
        ) : null}

        <p className="confirmation-window__expiry">
          Expires {confirmation.expiresAt}
          {confirmation.invalidation.invalidAfterPlanChange ? " · void if the plan changes" : ""}
          {confirmation.invalidation.singleUseToken ? " · single use" : ""}
        </p>

        <p className="confirmation-window__notice">{confirmation.executionNotice}</p>

        <div className="confirmation-window__choices">
          <button
            type="button"
            className="confirmation-choice confirmation-choice--cancel"
            ref={defaultIsReview ? undefined : defaultChoiceRef}
            onClick={() => decide("cancel")}
          >
            {choices.cancel.label}
          </button>
          <button
            type="button"
            className="confirmation-choice confirmation-choice--review"
            ref={defaultIsReview ? defaultChoiceRef : undefined}
            aria-pressed={reviewing}
            onClick={() => setReviewing((previous) => !previous)}
          >
            {choices.review.label}
          </button>
          <button
            type="button"
            className="confirmation-choice confirmation-choice--approve"
            disabled={readOnly}
            aria-disabled={readOnly || undefined}
            title={readOnly ? "Approval is disabled while the dashboard is read-only" : undefined}
            onClick={() => decide("approve")}
          >
            {choices.approve.label}
          </button>
        </div>
      </div>
    </>
  );
}

/** Overlay host slot: renders the confirmation window only while one is active (event-driven). */
export function ConfirmationOverlay() {
  const confirmation = useDashboardState().activeConfirmation ?? null;
  return confirmation ? <ConfirmationWindow confirmation={confirmation} /> : null;
}
