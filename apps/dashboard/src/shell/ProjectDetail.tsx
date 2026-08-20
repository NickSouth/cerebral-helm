import { useState } from "react";
import { Markdown } from "./Markdown";
import { ProjectCycleSection } from "./ProjectCycleSection";

/** The data the native shell injects for the expanded project detail window (NIC-129). */
export interface ProjectDetailData {
  readonly name: string;
  readonly markdownBody: string;
  /** The project's current `importance` (higher = more important); edited by the stepper. */
  readonly importance: number;
  /** The Linear project this folder tracks (NIC-221), or null when the descriptor declares none.
   *  Null is a normal state — the cycle section renders it as an invitation to link. */
  readonly linearProject: string | null;
}

/**
 * The expanded project detail view (NIC-129, NIC-221): a project's `PROJECT.md` rendered as
 * markdown, an editable priority (`importance`) stepper in the top bar, and — where the "Live
 * status" placeholder used to sit — the project's live Linear cycle.
 *
 * **Stacked, one scroll** (owner decision, 2026-08-20, chosen from a live mockup against the
 * tabbed alternative): the brief and the cycle share a single scroll container, so the brief is
 * always what you see first and the tickets are what you scroll into. That means the markdown body
 * no longer owns the scroll — the wrapper does — or the two would scroll independently and the
 * cycle's sticky headers would have nothing to stick to.
 *
 * Presentational apart from the cycle section, which fetches its own data: the native
 * `ProjectDetailWindowController` supplies the descriptor and hosts this in its own window, and
 * `ProjectDetailApp` wires close and set-importance to the shell-control channel.
 */
export function ProjectDetail({
  name,
  markdownBody,
  importance,
  linearProject,
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
      <div className="project-detail__scroll">
        <div className="project-detail__body">
          <Markdown source={markdownBody} />
        </div>
        <ProjectCycleSection linearProject={linearProject} />
      </div>
    </div>
  );
}
