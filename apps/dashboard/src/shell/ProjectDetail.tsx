import { useState } from "react";
import { Markdown } from "./Markdown";

/** The data the native shell injects for the expanded project detail window (NIC-129). */
export interface ProjectDetailData {
  readonly name: string;
  readonly markdownBody: string;
  /** The project's current `importance` (higher = more important); edited by the stepper. */
  readonly importance: number;
}

/**
 * The expanded project detail view (NIC-129): a project's `PROJECT.md` rendered as markdown,
 * an editable priority (`importance`) stepper in the top bar, and a placeholder "Live status"
 * section a later increment will populate (local repo signals first, Linear integration
 * eventually — the ticket defers both). Presentational: the native `ProjectDetailWindowController`
 * supplies the data and hosts this in its own window; `ProjectDetailApp` wires the close and
 * set-importance actions to the shell-control channel.
 */
export function ProjectDetail({
  name,
  markdownBody,
  importance,
  onClose,
  onSetImportance
}: ProjectDetailData & { onClose: () => void; onSetImportance: (value: number) => void }) {
  // Optimistic: the stepper owns the displayed number and reports each change; the native side
  // persists it and the widget reorders on its next scan (floored at 0, matching the writer).
  const [priority, setPriority] = useState(importance);
  const change = (delta: number) => {
    const next = Math.max(0, priority + delta);
    if (next === priority) return;
    setPriority(next);
    onSetImportance(next);
  };

  return (
    <div className="project-detail" role="main" aria-label={`Project: ${name}`}>
      <header className="project-detail__header">
        <h1 className="project-detail__title">{name}</h1>
        <div className="project-detail__priority" role="group" aria-label="Priority">
          <span className="project-detail__priority-label">Priority</span>
          <button
            type="button"
            className="project-detail__priority-step"
            aria-label="Decrease priority"
            disabled={priority <= 0}
            onClick={() => change(-1)}
          >
            −
          </button>
          <span className="project-detail__priority-value" aria-live="polite">
            {priority}
          </span>
          <button
            type="button"
            className="project-detail__priority-step"
            aria-label="Increase priority"
            onClick={() => change(1)}
          >
            +
          </button>
        </div>
        <button
          type="button"
          className="project-detail__close"
          aria-label="Close"
          onClick={onClose}
        >
          ×
        </button>
      </header>
      <div className="project-detail__body">
        <Markdown source={markdownBody} />
      </div>
      <section className="project-detail__status" aria-label="Live status">
        <h2 className="project-detail__status-title">Live status</h2>
        <p className="project-detail__status-note">
          Live status is coming soon — project state will appear here.
        </p>
      </section>
    </div>
  );
}
