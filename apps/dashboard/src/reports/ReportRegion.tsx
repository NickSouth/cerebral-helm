import { useCallback, useRef, useState, type RefObject } from "react";
import { useReportDocument } from "./useReportDocument";
import { renderableBlocks, type ReportActionReference, type ReportBlock } from "./reportDocument";
import { quickActionLabel } from "../shell/quickActionRegistry";
import { resolveQuickAction } from "../shell/quickActionHandlers";
import { useBridge } from "../state/BridgeProvider";
import { useActionStatus } from "../state/ActionStatusProvider";
import { useUiPosture } from "../state/useUiPosture";
import { useReports } from "../state/ReportProvider";
import { useInputs } from "../state/InputProvider";
import { useAppearance } from "../state/AppearanceProvider";
import { useTypewriter } from "../shell/useTypewriter";
import { useLeaveTransition } from "../shell/useLeaveTransition";

/**
 * The Report region (docs/quick-actions/PLAN.md): the centre panel's left third, from below the
 * Heimlich wordmark down to above the greeting. Opaque and borderless with a right-edge mask, so
 * the consciousness stream dissolves into it rather than being boxed away from it.
 *
 * This **is** the future conversation surface — same geometry, same renderer, plus scrollback and
 * a docked input. That is why blocks reveal top-down on a stagger: it reads well at this density
 * and maps directly onto a model streaming blocks in later, with no second surface to build.
 */
export function ReportRegion({
  contentRef,
  ready = true
}: {
  /** Attached to the block list so `CenterShade` can measure the text it has to hug. */
  contentRef?: RefObject<HTMLDivElement | null>;
  /**
   * False while the centre is still handing over — the ambient greeting is on its way out and this
   * surface must not appear on top of it. `CenterStage` owns that sequence, because it is the only
   * thing that can see both. Held *after* the hooks above so the report's own data keeps loading
   * during the handover: the wait is for the animation, not for the fetch.
   */
  ready?: boolean;
} = {}) {
  const { openReportId, openReportParams, closeReport } = useReports();
  // The outgoing report stays mounted until it has finished receding, so a swap is a handover
  // rather than a blink. Everything below renders `shown`, not the live id.
  const { shown: shownReportId, leaving } = useLeaveTransition(openReportId);
  const { document, refresh } = useReportDocument(shownReportId ?? "", undefined, openReportParams);
  const { reducedMotion } = useAppearance();
  const bodyRef = useRef<HTMLDivElement>(null);
  const caretRef = useRef<HTMLSpanElement>(null);

  // What the typewriter is keyed on, and why it is none of the obvious candidates.
  //
  // The document **object** is not identity: `useReportDocument` composes a fresh one on every
  // render, from a fresh `new Date()`. Keying on it restarts the animation on every re-render of
  // the dashboard — the report visibly rewrites itself forever.
  //
  // The document's **text** is not identity either, for the same reason: relative times ("in 20
  // minutes") drift on their own, so a clock tick would retype a report mid-read.
  //
  // What actually means "write this again" is: a different report opened, the reader asked for a
  // refresh, or the composition changed shape (a fetch resolving from its loading state into the
  // real thing). Block count is the cheap, stable expression of that last one — it survives a
  // re-render and a clock tick, and moves when the report genuinely becomes a different document.
  const [refreshCount, setRefreshCount] = useState(0);
  const rewrite = useCallback(() => {
    refresh();
    setRefreshCount((count) => count + 1);
  }, [refresh]);

  // Suppressed while leaving — a surface on its way out must not start rewriting itself — and
  // while the centre is still handing over, so the greeting is gone before this starts writing.
  const typewriterKey =
    document && !leaving && ready
      ? `${shownReportId}:${refreshCount}:${document.blocks.length}`
      : null;
  useTypewriter(bodyRef, typewriterKey, { enabled: !reducedMotion, caretRef });

  if (!shownReportId || !ready) {
    return null;
  }
  const openReportIdShown = shownReportId;

  const blocks = document ? renderableBlocks(document) : [];

  return (
    <section
      className="report-region"
      aria-label={`${quickActionLabel(openReportIdShown)} report`}
      data-report={openReportIdShown}
      data-leaving={leaving || undefined}
    >
      {/* OUTSIDE the scroller. A halo paints beyond its element's box and `overflow-y: auto` clips
          on both axes, so anything haloed inside a scroll container gets its shade sheared off
          square at that container's edges. The header does not need to scroll anyway. */}
      <header className="report-region__head">
        <h2 className="report-region__title">{quickActionLabel(openReportIdShown)}</h2>
        {/* Only for a report composed from a fetch: offering a refresh on a document built from
            ambient state would promise something it cannot do. */}
        {document?.refreshable ? (
          <button
            type="button"
            className="report-region__refresh"
            aria-label={`Refresh the ${quickActionLabel(openReportIdShown)} report`}
            onClick={rewrite}
          >
            Refresh
          </button>
        ) : null}
        <button
          type="button"
          className="report-region__close"
          aria-label={`Close the ${quickActionLabel(openReportIdShown)} report`}
          onClick={closeReport}
        >
          ×
        </button>
      </header>

      <div className="report-region__scroll">
        {/* One element, two readers: the shade measures it, the typewriter walks it. */}
        <div
          className="report-region__content"
          ref={(node) => {
            bodyRef.current = node;
            if (contentRef) {
              contentRef.current = node;
            }
          }}
        >
          {document === null ? (
            // Registered as a Report with no composer yet. Honest-unavailable beats an empty
            // document, which would read as "your brief is genuinely empty".
            <p className="report-region__pending">This report isn’t built yet.</p>
          ) : (
            <ReportBlocks blocks={blocks} />
          )}
          {/* Positioned by the typewriter from a collapsed range, so it lands wherever the text
              actually wrapped to rather than at a guessed offset. */}
          <span className="report-caret" ref={caretRef} aria-hidden="true" />
        </div>
      </div>
    </section>
  );
}

/**
 * The block list, exported because it is the seam a streaming composer renders into: today it
 * receives a finished document's blocks, later it receives however many a model has emitted so
 * far. Nothing about the markup changes between those two cases.
 */
export function ReportBlocks({ blocks }: { blocks: readonly ReportBlock[] }) {
  return (
    <div className="report-region__blocks">
      {blocks.map((block, index) => (
        <div key={`${block.blockKind}-${index}`} className="report-region__block">
          <BlockView block={block} />
        </div>
      ))}
    </div>
  );
}

/**
 * A clickable span inside a report. The destination is an **action reference** resolved through
 * the dispatch registry — never an href — so a model composing this document can only ever point
 * at a registered action, and the tool behind it builds its own destination host-side.
 *
 * An unregistered or unbuilt action renders as plain text rather than a dead control: the report
 * still reads correctly, it just isn't clickable.
 */
function ActionLink({
  reference,
  children,
  className
}: {
  reference: ReportActionReference;
  children: React.ReactNode;
  className: string;
}) {
  const bridge = useBridge();
  const { announce } = useActionStatus();
  const { readOnly } = useUiPosture();
  const { openReport } = useReports();
  const { openInput } = useInputs();
  // The full dispatch deps, so a reference can reach every archetype — a proposal offering
  // "create an event" must open that form, not fall back to plain text. Params ride along to the
  // handler, which validates them; they are untrusted by construction, since once a model
  // composes the document it chooses these values.
  const activate = readOnly
    ? null
    : resolveQuickAction(
        reference.action,
        { bridge, announce, openReport, openInput },
        reference.params
      );

  if (!activate) {
    return <span className={className}>{children}</span>;
  }
  return (
    <button type="button" className={`${className} report-link`} onClick={activate}>
      {children}
    </button>
  );
}

/** Renders one block. Every kind is drawn from the fields its kind declares — nothing else. */
function BlockView({ block }: { block: ReportBlock }) {
  switch (block.blockKind) {
    case "greeting":
      return (
        <p className="report-greeting" data-size={block.greetingSize ?? "standard"}>
          {block.text}
        </p>
      );

    case "line": {
      const line = (
        <span className="report-line__text" data-emphasis={block.lineEmphasis ?? "normal"}>
          {block.text}
        </span>
      );
      return (
        <p className="report-line">
          {block.reportAction ? (
            <ActionLink reference={block.reportAction} className="report-line__text">
              {block.text}
            </ActionLink>
          ) : (
            line
          )}
        </p>
      );
    }

    case "metric":
      return (
        <p className="report-metric" data-tone={block.metricTone ?? "neutral"}>
          <span className="report-metric__label">{block.label}</span>
          <span className="report-metric__value">{block.value}</span>
        </p>
      );

    case "count": {
      const body = (
        <>
          <span className="report-count__value">{block.value}</span>
          <span className="report-count__label">{block.label}</span>
        </>
      );
      return (
        <p className="report-count">
          {block.reportAction ? (
            <ActionLink reference={block.reportAction} className="report-count__body">
              {body}
            </ActionLink>
          ) : (
            <span className="report-count__body">{body}</span>
          )}
        </p>
      );
    }

    case "list":
    case "checklist":
      return (
        <ul className="report-list" data-variant={block.blockKind}>
          {(block.listItems ?? []).map((item, index) => (
            <li key={`${item.text}-${index}`} className="report-list__item">
              <span
                className="report-list__dot"
                data-status={item.status ?? undefined}
                style={item.color ? { background: item.color } : undefined}
                aria-hidden="true"
              />
              {item.reportAction ? (
                <ActionLink reference={item.reportAction} className="report-list__text">
                  {item.text}
                </ActionLink>
              ) : (
                <span className="report-list__text">{item.text}</span>
              )}
              {item.meta ? <span className="report-list__meta">{item.meta}</span> : null}
              {item.status ? <span className="sr-only">{item.status}</span> : null}
            </li>
          ))}
        </ul>
      );

    case "empty":
      return <p className="report-empty">{block.text}</p>;

    case "scoreboard":
      return <ScoreboardView block={block} />;
    case "leaderboard":
      return <LeaderboardView block={block} />;
    case "proposal":
      return (
        <div className="report-proposal">
          {block.text ? <p className="report-proposal__text">{block.text}</p> : null}
          <div className="report-proposal__actions">
            {(block.reportActions ?? []).map((reference, index) => (
              <ActionLink
                key={`${reference.action}-${index}`}
                reference={reference}
                className="report-proposal__action"
              >
                {quickActionLabel(reference.action)}
              </ActionLink>
            ))}
          </div>
        </div>
      );

    default:
      // Unreachable for a well-formed document (renderableBlocks already dropped unknown kinds),
      // and deliberately silent rather than throwing if a future composer invents one.
      return null;
  }
}

/**
 * A team game: two sides, each carrying its own colour.
 *
 * The colour is a thin accent bar rather than a fill — a scoreboard tile flooded with team colour
 * would be the loudest thing in a dashboard built on one accent per mode, and the report's own
 * rule is that colour means *actionable*. A bar reads as identity without claiming to be a link.
 */
function ScoreboardView({ block }: { block: ReportBlock }) {
  const sides = block.scoreboardSides ?? [];
  return (
    <div className="report-scoreboard">
      {sides.map((side) => (
        <div className="report-scoreboard__side" key={side.sideAbbreviation}>
          <span
            className="report-scoreboard__accent"
            aria-hidden="true"
            /* The provider sends bare hex; the `#` is added here rather than stored, so a value
               that is not a colour at all simply fails to apply instead of corrupting the style. */
            style={side.sideColor ? { background: `#${side.sideColor}` } : undefined}
          />
          <span className="report-scoreboard__abbr">{side.sideAbbreviation}</span>
          {side.sideRecord ? (
            <span className="report-scoreboard__record">{side.sideRecord}</span>
          ) : null}
          <span className="report-scoreboard__score">{side.sideScore}</span>
        </div>
      ))}
      {block.text ? <p className="report-scoreboard__status">{block.text}</p> : null}
    </div>
  );
}

/**
 * A ranked field, showing `leaderboardPreview` rows until the reader expands it.
 *
 * The expansion is **local render state over a complete list**, not a re-fetch: the document
 * already holds every row, because the host paid for them once and re-reading a megabyte to
 * reveal rows it already had would be absurd. That is also why the block carries the whole field
 * rather than a truncated one — a document that only contained ten rows could not expand at all.
 */
function LeaderboardView({ block }: { block: ReportBlock }) {
  const rows = block.leaderboardRows ?? [];
  const preview = block.leaderboardPreview ?? rows.length;
  const [expanded, setExpanded] = useState(false);
  const shown = expanded ? rows : rows.slice(0, preview);
  const hidden = rows.length - shown.length;

  return (
    <div className="report-leaderboard">
      <ol className="report-leaderboard__rows">
        {shown.map((row, index) => (
          <li className="report-leaderboard__row" key={`${row.rowName}-${index}`}>
            <span className="report-leaderboard__position">{row.rowPosition ?? index + 1}</span>
            <span className="report-leaderboard__name">{row.rowName}</span>
            {/* `thru` exists only mid-round, so its absence shortens the row rather than
                printing an empty column. */}
            {row.rowThru ? (
              <span className="report-leaderboard__thru">thru {row.rowThru}</span>
            ) : null}
            <span className="report-leaderboard__score">{row.rowScore}</span>
          </li>
        ))}
      </ol>
      {hidden > 0 || expanded ? (
        <button
          type="button"
          className="report-leaderboard__more"
          onClick={() => setExpanded((current) => !current)}
        >
          {expanded ? "Show less" : `Show all ${rows.length}`}
        </button>
      ) : null}
    </div>
  );
}
