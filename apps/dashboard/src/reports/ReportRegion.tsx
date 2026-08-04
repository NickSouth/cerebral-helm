import { useReportDocument } from "./useReportDocument";
import { renderableBlocks, type ReportActionReference, type ReportBlock } from "./reportDocument";
import { quickActionLabel } from "../shell/quickActionRegistry";
import { resolveQuickAction } from "../shell/quickActionHandlers";
import { useBridge } from "../state/BridgeProvider";
import { useActionStatus } from "../state/ActionStatusProvider";
import { useUiPosture } from "../state/useUiPosture";
import { useReports } from "../state/ReportProvider";
import { useInputs } from "../state/InputProvider";

/**
 * The Report region (docs/quick-actions/PLAN.md): the centre panel's left third, from below the
 * Heimlich wordmark down to above the greeting. Opaque and borderless with a right-edge mask, so
 * the consciousness stream dissolves into it rather than being boxed away from it.
 *
 * This **is** the future conversation surface — same geometry, same renderer, plus scrollback and
 * a docked input. That is why blocks reveal top-down on a stagger: it reads well at this density
 * and maps directly onto a model streaming blocks in later, with no second surface to build.
 */
export function ReportRegion() {
  const { openReportId, closeReport } = useReports();
  const document = useReportDocument(openReportId ?? "");

  if (!openReportId) {
    return null;
  }

  const blocks = document ? renderableBlocks(document) : [];

  return (
    <section
      className="report-region"
      aria-label={`${quickActionLabel(openReportId)} report`}
      data-report={openReportId}
    >
      <header className="report-region__head">
        <h2 className="report-region__title">{quickActionLabel(openReportId)}</h2>
        <button
          type="button"
          className="report-region__close"
          aria-label={`Close the ${quickActionLabel(openReportId)} report`}
          onClick={closeReport}
        >
          ×
        </button>
      </header>

      {document === null ? (
        // Registered as a Report with no composer yet. Honest-unavailable beats an empty
        // document, which would read as "your brief is genuinely empty".
        <p className="report-region__pending">This report isn’t built yet.</p>
      ) : (
        <ReportBlocks blocks={blocks} />
      )}
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
        <div
          key={`${block.blockKind}-${index}`}
          className="report-region__block"
          /* Per-block delay drives the top-down stagger; the same mechanism carries a model's
             streamed blocks later. */
          style={{ "--ch-report-block-index": index } as React.CSSProperties}
        >
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
