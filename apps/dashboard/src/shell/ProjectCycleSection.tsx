import { useCallback, useEffect, useState } from "react";
import { SkeletonBone } from "../components/Skeleton";
import { useBridge } from "../state/BridgeProvider";
import { useUiPosture } from "../state/useUiPosture";
import { submitWebOpen } from "./webOpen";
import type { GetLinearProjectCycleResult, LinearCycleIssue } from "../bridge/cerebralBridge";

/**
 * The project detail window's live Linear section (NIC-221): the issues of this project's linked
 * Linear project that sit in the currently-active cycle, stacked by status the way Linear's own
 * list view stacks them.
 *
 * Fetched once when the window opens rather than streamed. The window is built fresh on every open
 * (`WindowCoordinator.openProjectDetail`) and is a short-lived reading pane, so a publisher would
 * be machinery for a surface that outlives one glance.
 *
 * ## Why there are six empty-ish states and not one
 *
 * Zero rows can mean six different things, and five of them are the user's to act on. Collapsing
 * any of them into "nothing to do" produces the worst failure this surface has: a confident,
 * wrong answer that looks like an answer. So each is named separately —
 *
 * - the descriptor declares no `linear_project` (unlinked)
 * - this host has no Linear client at all (`available: false`)
 * - the read was attempted and failed (`reason`)
 * - the name matches no Linear project (`matchedProject: null` — a typo in the descriptor)
 * - no cycle is currently running (`cycle: null` — between cycles)
 * - the project matched, a cycle is running, and it genuinely holds nothing
 */

/** Most-active-first. Deliberately NOT Linear's board order: on a glance surface the thing you are
 *  doing outranks the thing you finished. Within a type, Linear's own `position` decides, so
 *  reordering statuses in Linear reorders them here with no code change. */
const TYPE_RANK: Record<string, number> = {
  started: 0,
  unstarted: 1,
  backlog: 2,
  completed: 3,
  canceled: 4
};

const PRIORITY_LABEL: Record<number, string> = {
  0: "No priority",
  1: "Urgent",
  2: "High",
  3: "Medium",
  4: "Low"
};

interface StatusGroup {
  readonly key: string;
  readonly name: string;
  readonly type: string;
  readonly color: string;
  readonly issues: readonly LinearCycleIssue[];
}

/** Groups issues by workflow state, ordered most-active-first then by Linear's own position.
 *  Exported for its own test — the ordering is the part most likely to drift. */
export function groupByStatus(issues: readonly LinearCycleIssue[]): StatusGroup[] {
  const groups = new Map<string, LinearCycleIssue[]>();
  for (const issue of issues) {
    const existing = groups.get(issue.state.name);
    if (existing) {
      existing.push(issue);
    } else {
      groups.set(issue.state.name, [issue]);
    }
  }
  return [...groups.entries()]
    .map(([name, grouped]) => ({
      key: name,
      name,
      type: grouped[0].state.type,
      color: grouped[0].state.color,
      // Linear's manual order within a status.
      issues: [...grouped].sort((a, b) => a.sortOrder - b.sortOrder)
    }))
    .sort((a, b) => {
      const rank =
        (TYPE_RANK[a.type] ?? Number.MAX_SAFE_INTEGER) -
        (TYPE_RANK[b.type] ?? Number.MAX_SAFE_INTEGER);
      if (rank !== 0) return rank;
      const position = a.issues[0].state.position - b.issues[0].state.position;
      return position !== 0 ? position : a.name.localeCompare(b.name);
    });
}

/** "17–24 Aug", collapsing a shared month rather than repeating it. */
export function formatCycleRange(startsAt: string, endsAt: string): string {
  const start = new Date(startsAt);
  const end = new Date(endsAt);
  if (Number.isNaN(start.valueOf()) || Number.isNaN(end.valueOf())) return "";
  const day = (date: Date) => date.getDate();
  const month = (date: Date) => date.toLocaleString(undefined, { month: "short" });
  return start.getMonth() === end.getMonth()
    ? `${day(start)}–${day(end)} ${month(end)}`
    : `${day(start)} ${month(start)} – ${day(end)} ${month(end)}`;
}

/** Whole days from `now` until the cycle closes; null once it has closed. */
export function daysRemaining(endsAt: string, now: Date = new Date()): number | null {
  const end = new Date(endsAt);
  if (Number.isNaN(end.valueOf())) return null;
  const days = Math.ceil((end.valueOf() - now.valueOf()) / 86_400_000);
  return days >= 0 ? days : null;
}

/** Linear's status donut. The ring plus a wedge for how far through the workflow the state sits,
 *  and a check once complete — the fill IS the status, which is what lets the list be read
 *  without leaning on the labels. Colour is always Linear's own. */
function StatusIcon({ type, color }: { type: string; color: string }) {
  if (type === "completed") {
    return (
      <svg className="cyc-icon" viewBox="0 0 14 14" aria-hidden="true">
        <circle cx="7" cy="7" r="6" fill={color} />
        <path
          d="M4.2 7.2 L6.1 9.1 L9.8 5.1"
          fill="none"
          stroke="var(--ch-bg-base)"
          strokeWidth="1.6"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
    );
  }
  if (type === "canceled") {
    return (
      <svg className="cyc-icon" viewBox="0 0 14 14" aria-hidden="true">
        <circle cx="7" cy="7" r="6" fill={color} opacity="0.5" />
        <path
          d="M4.8 4.8 L9.2 9.2 M9.2 4.8 L4.8 9.2"
          stroke="var(--ch-bg-base)"
          strokeWidth="1.6"
          strokeLinecap="round"
        />
      </svg>
    );
  }
  // Ring plus wedge: one stroked circle with a dash offset, so a single fraction drives it.
  const radius = 3.1;
  const circumference = 2 * Math.PI * radius;
  const fill = type === "started" ? 0.5 : 0;
  return (
    <svg className="cyc-icon" viewBox="0 0 14 14" aria-hidden="true">
      <circle
        cx="7"
        cy="7"
        r="5.4"
        fill="none"
        stroke={color}
        strokeWidth="1.4"
        strokeDasharray={type === "backlog" ? "2 2.2" : undefined}
        opacity="0.9"
      />
      {fill > 0 ? (
        <circle
          cx="7"
          cy="7"
          r={radius}
          fill="none"
          stroke={color}
          strokeWidth={radius * 2}
          strokeDasharray={`${circumference * fill} ${circumference}`}
          transform="rotate(-90 7 7)"
        />
      ) : null}
    </svg>
  );
}

/** Linear's priority glyph: three bars filled to the level. "No priority" is one quiet dash —
 *  most of a personal cycle has none, and it must not add noise. */
function PriorityIcon({ priority }: { priority: number }) {
  if (priority === 0) {
    return (
      <svg className="cyc-pri" viewBox="0 0 12 12" aria-hidden="true">
        <rect x="1" y="5.4" width="10" height="1.3" rx="0.6" fill="currentColor" opacity="0.42" />
      </svg>
    );
  }
  if (priority === 1) {
    return (
      <svg className="cyc-pri" viewBox="0 0 12 12" aria-hidden="true">
        <rect x="1.6" y="1" width="8.8" height="10" rx="2" fill="var(--ch-status-error)" />
        <rect x="5.4" y="3" width="1.2" height="4" rx="0.6" fill="var(--ch-bg-base)" />
        <rect x="5.4" y="8" width="1.2" height="1.3" rx="0.6" fill="var(--ch-bg-base)" />
      </svg>
    );
  }
  const lit = priority === 2 ? 3 : priority === 3 ? 2 : 1;
  const bars: Array<[number, number, number]> = [
    [1, 7.2, 3.8],
    [4.4, 4.6, 6.4],
    [7.8, 2, 9]
  ];
  return (
    <svg className="cyc-pri" viewBox="0 0 12 12" aria-hidden="true">
      {bars.map(([x, y, height], index) => (
        <rect
          key={x}
          x={x}
          y={y}
          width="2.4"
          height={height}
          rx="0.8"
          fill="currentColor"
          opacity={index < lit ? 0.85 : 0.25}
        />
      ))}
    </svg>
  );
}

function CycleSkeleton() {
  return (
    <div className="cyc__loading" aria-hidden="true">
      <SkeletonBone className="cyc__bone-head" />
      {[0, 1, 2, 3].map((row) => (
        <SkeletonBone key={row} className="cyc__bone-row" />
      ))}
    </div>
  );
}

/** A named non-list state. `action` is an optional "open it in Linear" escape hatch. */
function CycleState({
  title,
  children,
  action
}: {
  title: string;
  children: React.ReactNode;
  action?: { label: string; url: string; disabled: boolean };
}) {
  const bridge = useBridge();
  return (
    <div className="cyc__state">
      <p className="cyc__state-title">{title}</p>
      {/* A div, not a p: the picker is a block element and some states nest it in here, which a
          paragraph cannot legally contain. */}
      <div className="cyc__state-note">{children}</div>
      {action ? (
        <button
          type="button"
          className="cyc__state-action"
          disabled={action.disabled}
          onClick={() => {
            void submitWebOpen(bridge, action.url);
          }}
        >
          {action.label}
        </button>
      ) : null}
    </div>
  );
}

/**
 * Offers the workspace's Linear projects and reports the chosen one (NIC-221, Increment 6).
 *
 * Reads through `listLinearOptions`, the read closure the create-ticket form already uses, rather
 * than a new surface: it returns every team with its projects, which is exactly the list needed
 * here. Names are flattened and de-duplicated because the descriptor stores a NAME — two projects
 * sharing one across teams would be ambiguous to write down, so they are shown once.
 *
 * Loads its options only when the picker is actually rendered, which is the unlinked and
 * broken-link states — the common case never pays for a request it does not use.
 */
function LinearProjectPicker({ onPick }: { onPick: (project: string) => void }) {
  const bridge = useBridge();
  const { readOnly } = useUiPosture();
  const [projects, setProjects] = useState<readonly string[] | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let live = true;
    bridge
      .listLinearOptions()
      .then((options) => {
        if (!live) return;
        if (!options.available) {
          setFailed(true);
          return;
        }
        const names = new Set<string>();
        for (const team of options.teams) {
          for (const project of team.projects) names.add(project.name);
        }
        setProjects([...names].sort((a, b) => a.localeCompare(b)));
      })
      .catch(() => {
        if (live) setFailed(true);
      });
    return () => {
      live = false;
    };
  }, [bridge]);

  if (failed) return null;
  if (!projects) {
    return (
      <div className="cyc__picker" aria-hidden="true">
        <SkeletonBone className="cyc__bone-chip" />
        <SkeletonBone className="cyc__bone-chip" />
      </div>
    );
  }
  if (projects.length === 0) return null;

  return (
    <div className="cyc__picker" role="group" aria-label="Link to a Linear project">
      {projects.map((project) => (
        <button
          key={project}
          type="button"
          className="cyc__picker-option"
          disabled={readOnly}
          title={
            readOnly
              ? "Linking is paused while the dashboard is read-only"
              : `Link this project to ${project}`
          }
          onClick={() => {
            onPick(project);
          }}
        >
          {project}
        </button>
      ))}
    </div>
  );
}

/**
 * The link affordance for a project that has no Linear link yet (NIC-221, Increment 6).
 *
 * A single button first, the list of projects only once asked for. An unlinked project is the
 * FIRST thing you see in a window you opened to read a brief, and a row of every project in the
 * workspace is a decision demanded before you have said you want to make one. The button states
 * the offer; the list answers it.
 */
function LinkAffordance({ onPick }: { onPick: (project: string) => void }) {
  const { readOnly } = useUiPosture();
  const [picking, setPicking] = useState(false);

  if (picking) return <LinearProjectPicker onPick={onPick} />;

  return (
    <button
      type="button"
      className="cyc__state-action"
      disabled={readOnly}
      title={
        readOnly
          ? "Linking is paused while the dashboard is read-only"
          : "Choose the Linear project this tracks"
      }
      onClick={() => {
        setPicking(true);
      }}
    >
      Link here
    </button>
  );
}

export function ProjectCycleSection({
  linearProject,
  onSetLinearProject
}: {
  linearProject: string | null;
  /** Persist a newly-picked Linear project into `PROJECT.md` (NIC-221, Increment 6). Absent in a
   *  browser preview, where there is no descriptor to write to. */
  onSetLinearProject?: (project: string) => void;
}) {
  const bridge = useBridge();
  const { readOnly } = useUiPosture();
  const [result, setResult] = useState<GetLinearProjectCycleResult | null>(null);
  const [failed, setFailed] = useState(false);
  // The link the section is currently showing. Seeded from the descriptor and advanced when the
  // user picks one, so the cycle appears immediately rather than on the next window open — the
  // native side re-reads the descriptor, but this window already knows the answer.
  const [project, setProject] = useState(linearProject);

  useEffect(() => {
    setProject(linearProject);
  }, [linearProject]);

  useEffect(() => {
    if (!project) return;
    let live = true;
    setResult(null);
    setFailed(false);
    bridge
      .getLinearProjectCycle(project)
      .then((next) => {
        if (live) setResult(next);
      })
      .catch(() => {
        if (live) setFailed(true);
      });
    return () => {
      live = false;
    };
  }, [bridge, project]);

  const link = (picked: string) => {
    onSetLinearProject?.(picked);
    setProject(picked);
  };

  // The group headers stack under the cycle header, so their sticky offset is its real height.
  // Measured rather than hardcoded: the height moves with the root font size, which this app
  // derives from viewport height, and a stale constant leaves a sliver the rows scroll through.
  //
  // The variable is set on the SECTION, not on the header: the group headers are the header's
  // siblings, and a custom property inherits down the tree, never sideways. Setting it on the
  // header itself looks right and silently leaves every group on the fallback.
  const measureHead = useCallback((node: HTMLDivElement | null) => {
    const section = node?.parentElement;
    if (!node || !section) return;
    const apply = () =>
      section.style.setProperty(
        "--cyc-head-h",
        `${Math.round(node.getBoundingClientRect().height)}px`
      );
    apply();
    if (typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(apply);
    observer.observe(node);
  }, []);

  const open = (issue: LinearCycleIssue) => {
    void submitWebOpen(bridge, issue.url);
  };

  const body = () => {
    if (!project) {
      return (
        <CycleState title="Not currently linked to a Linear project">
          Link it here and CerebralHelm writes <code>linear_project</code> into this
          project&rsquo;s <code>PROJECT.md</code> — the same place <code>importance</code> lives.
          <LinkAffordance onPick={link} />
        </CycleState>
      );
    }
    if (failed) {
      return (
        <CycleState title="Couldn&rsquo;t reach Linear">
          The request did not complete. Reopening this project will try again.
        </CycleState>
      );
    }
    if (!result) return <CycleSkeleton />;
    if (!result.available) {
      return (
        <CycleState title="Linear isn&rsquo;t set up">
          Add a Linear API key under Settings → Setup to see this project&rsquo;s cycle.
        </CycleState>
      );
    }
    if (result.reason) {
      return (
        <CycleState title="Couldn&rsquo;t read Linear">{result.reason}</CycleState>
      );
    }
    if (result.matchedProject === null) {
      // A typo in the descriptor, not an empty week. Named separately because it is fixable and
      // because it is otherwise byte-identical to an empty cycle.
      return (
        <CycleState title="No Linear project by that name">
          Nothing in Linear is called <code>{project}</code>. Pick the right one, or fix the{" "}
          <code>linear_project</code> key in this project&rsquo;s <code>PROJECT.md</code>.
          <LinearProjectPicker onPick={link} />
        </CycleState>
      );
    }
    if (!result.cycle) {
      return (
        <CycleState
          title="No cycle running"
          action={
            result.matchedProjectUrl
              ? { label: "Open in Linear", url: result.matchedProjectUrl, disabled: readOnly }
              : undefined
          }
        >
          <b>{result.matchedProject}</b> is linked, but no cycle is active right now.
        </CycleState>
      );
    }
    if (result.issues.length === 0) {
      return (
        <CycleState
          title="Nothing in this cycle"
          action={
            result.matchedProjectUrl
              ? { label: "Open in Linear", url: result.matchedProjectUrl, disabled: readOnly }
              : undefined
          }
        >
          <b>{result.matchedProject}</b> has no issues in Cycle {result.cycle.number}.
        </CycleState>
      );
    }

    const groups = groupByStatus(result.issues);
    const done = result.issues.filter((issue) => issue.state.type === "completed").length;
    const started = result.issues.filter((issue) => issue.state.type === "started").length;
    const total = result.issues.length;
    const percent = (count: number) => `${((count / total) * 100).toFixed(1)}%`;
    const left = daysRemaining(result.cycle.endsAt);

    return (
      <>
        <div className="cyc__head" ref={measureHead}>
          <div className="cyc__label">
            <span className="cyc__name">
              {result.cycle.name ?? `Cycle ${result.cycle.number}`}
            </span>
            <span className="cyc__dates">
              {formatCycleRange(result.cycle.startsAt, result.cycle.endsAt)}
              {left === null ? "" : ` · ${left === 0 ? "last day" : `${left} days left`}`}
            </span>
          </div>
          {result.matchedProjectUrl ? (
            <button
              type="button"
              className="cyc__link"
              disabled={readOnly}
              title={`Open ${result.matchedProject} in Linear`}
              onClick={() => {
                void submitWebOpen(bridge, result.matchedProjectUrl as string);
              }}
            >
              Linear ↗
            </button>
          ) : null}
          <div className="cyc__progress">
            <span className="cyc__bar">
              <i style={{ width: percent(done) }} />
              <i style={{ left: percent(done), width: percent(started) }} />
            </span>
            <span className="cyc__count">
              {done} / {total} done
            </span>
          </div>
        </div>

        {groups.map((group) => (
          <div key={group.key}>
            <div className="cyc-grp">
              <StatusIcon type={group.type} color={group.color} />
              <span className="cyc-grp__name">{group.name}</span>
              <span className="cyc-grp__count">{group.issues.length}</span>
            </div>
            {group.issues.map((issue) => (
              <button
                key={issue.identifier}
                type="button"
                className="cyc-tk"
                disabled={readOnly}
                aria-disabled={readOnly || undefined}
                title={
                  readOnly
                    ? "Opening an issue is paused while the dashboard is read-only"
                    : `Open ${issue.identifier} in Linear`
                }
                onClick={() => {
                  open(issue);
                }}
              >
                <span className="cyc-tk__pri" title={PRIORITY_LABEL[issue.priority] ?? ""}>
                  <PriorityIcon priority={issue.priority} />
                </span>
                <span className="cyc-tk__id">{issue.identifier}</span>
                <span className="cyc-tk__title">{issue.title}</span>
                <span className="cyc-tk__meta">
                  {issue.labels.map((label) => (
                    <span key={label} className="cyc-tk__label">
                      {label}
                    </span>
                  ))}
                  <span className="cyc-tk__est">{issue.estimate ?? ""}</span>
                  {issue.assigneeInitials ? (
                    <span className="cyc-tk__av" title={issue.assignee ?? undefined}>
                      {issue.assigneeInitials}
                    </span>
                  ) : (
                    // Holds the slot so the right edge stays straight, but draws nothing: in a
                    // one-person workspace a marker on almost every row is noise, not information.
                    <span className="cyc-tk__av cyc-tk__av--none" />
                  )}
                  <span className="cyc-tk__go" aria-hidden="true">
                    ↗
                  </span>
                </span>
              </button>
            ))}
          </div>
        ))}

        {result.truncated ? (
          <p className="cyc__truncated">
            Showing the first {total} — this cycle holds more than one page.
          </p>
        ) : null}
      </>
    );
  };

  return (
    <section className="cyc" aria-label="Linear cycle">
      {body()}
    </section>
  );
}

export default ProjectCycleSection;
