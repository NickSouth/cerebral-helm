import { useUiPosture, type UiPosture } from "../state/useUiPosture";

/**
 * The content for one degraded top-level posture. `tone` is carried in text + a data attribute
 * (never color alone — constitution §2). `action` is a *specific* recovery affordance (NIC-64
 * AC "recovery actions are specific"); reloading is non-mutating, so it is honest even under a
 * read-only posture (AC "read-only recovery never exposes mutating controls" — reload does not
 * mutate user state).
 */
interface BannerContent {
  readonly tone: "offline" | "recovery" | "error";
  readonly title: string;
  readonly detail: string;
  readonly actionLabel: string;
}

function contentFor(posture: UiPosture): BannerContent | null {
  // Recovery is the strongest posture — surface it even if uiState also reads offline.
  if (posture.recovering) {
    return {
      tone: "recovery",
      title: "Read-only recovery",
      detail: posture.recoveryReason ?? "Startup entered read-only recovery; your data is preserved and unchanged.",
      actionLabel: "Reload dashboard"
    };
  }
  if (posture.offline) {
    return {
      tone: "offline",
      title: "Dashboard is offline",
      detail: "Showing the last-known information. Live actions are paused until the connection returns.",
      actionLabel: "Retry connection"
    };
  }
  if (posture.error) {
    return {
      tone: "error",
      title: "Something went wrong",
      detail: "The dashboard hit an error loading live data. Your saved information is unchanged.",
      actionLabel: "Reload dashboard"
    };
  }
  return null;
}

/** The honest recovery for every degraded posture pre-Mac: reload the shell. Guarded for jsdom. */
function reload(): void {
  if (typeof window !== "undefined" && typeof window.location?.reload === "function") {
    window.location.reload();
  }
}

/**
 * The top-level degraded-state ribbon (NIC-64): a full-width banner above the canvas for the
 * offline / read-only-recovery / error postures. It never replaces the dashboard — the shell
 * still renders its last-known-safe data beneath (AC "no blank screens"). Its only control is a
 * non-mutating recovery action, so it is safe under a read-only posture.
 */
export function SystemStatusBanner({ onRecover = reload }: { onRecover?: () => void } = {}) {
  const posture = useUiPosture();
  const content = contentFor(posture);
  if (!content) {
    return null;
  }

  return (
    <div className="system-banner" data-tone={content.tone} role="status" aria-live="polite">
      <span className="system-banner__mark" aria-hidden="true" />
      <span className="system-banner__text">
        <span className="system-banner__title">{content.title}</span>
        <span className="system-banner__detail">{content.detail}</span>
      </span>
      <button type="button" className="system-banner__action" onClick={onRecover}>
        {content.actionLabel}
      </button>
    </div>
  );
}
