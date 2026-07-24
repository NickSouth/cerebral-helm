import type { ReactNode } from "react";

/**
 * A deliberately tiny, dependency-free Markdown renderer for project descriptors (NIC-129).
 *
 * TECH-STACK (line 155) forbids loading arbitrary third-party code into the app process, and
 * `PROJECT.md` descriptors only need a small, well-known subset, so this renders exactly that
 * subset and nothing else: ATX headings (`#`..`######`), unordered lists (`-`/`*`/`+`),
 * paragraphs, and inline **bold** and _italic_. Anything outside the subset — including any
 * raw HTML — is rendered as literal text: the renderer only ever produces React nodes (never
 * `dangerouslySetInnerHTML`), so a descriptor can never inject markup or script.
 */
export function Markdown({ source }: { source: string }) {
  return <div className="md">{renderBlocks(source)}</div>;
}

const BOLD_OR_ITALIC = /(\*\*|__)(.+?)\1|(\*|_)(.+?)\3/g;
const HEADING = /^(#{1,6})\s+(.*)$/;
const LIST_ITEM = /^\s*[-*+]\s+(.*)$/;

/** Parse inline bold/italic within a run of text into React nodes (no nesting). */
function renderInline(text: string, keyPrefix: string): ReactNode[] {
  const nodes: ReactNode[] = [];
  // A fresh RegExp per call — a `g`-flagged literal keeps `lastIndex` state across calls.
  const pattern = new RegExp(BOLD_OR_ITALIC);
  let lastIndex = 0;
  let count = 0;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(text)) !== null) {
    if (match.index > lastIndex) {
      nodes.push(text.slice(lastIndex, match.index));
    }
    if (match[1] !== undefined) {
      nodes.push(<strong key={`${keyPrefix}-s${count}`}>{match[2]}</strong>);
    } else {
      nodes.push(<em key={`${keyPrefix}-e${count}`}>{match[4]}</em>);
    }
    lastIndex = pattern.lastIndex;
    count += 1;
  }
  if (lastIndex < text.length) {
    nodes.push(text.slice(lastIndex));
  }
  return nodes;
}

/** A heading element at the parsed level — an explicit switch so no dynamic tag is needed. */
function heading(level: number, children: ReactNode, key: string): ReactNode {
  switch (level) {
    case 1:
      return <h1 key={key} className="md-heading">{children}</h1>;
    case 2:
      return <h2 key={key} className="md-heading">{children}</h2>;
    case 3:
      return <h3 key={key} className="md-heading">{children}</h3>;
    case 4:
      return <h4 key={key} className="md-heading">{children}</h4>;
    case 5:
      return <h5 key={key} className="md-heading">{children}</h5>;
    default:
      return <h6 key={key} className="md-heading">{children}</h6>;
  }
}

/** Split the source into headings, unordered lists, and paragraphs. */
function renderBlocks(source: string): ReactNode[] {
  const lines = source.replace(/\r\n/g, "\n").split("\n");
  const blocks: ReactNode[] = [];
  let i = 0;
  let key = 0;
  while (i < lines.length) {
    if (lines[i].trim() === "") {
      i += 1;
      continue;
    }

    const headingMatch = HEADING.exec(lines[i]);
    if (headingMatch) {
      const blockKey = `b${key}`;
      blocks.push(heading(headingMatch[1].length, renderInline(headingMatch[2], blockKey), blockKey));
      key += 1;
      i += 1;
      continue;
    }

    if (LIST_ITEM.test(lines[i])) {
      const items: ReactNode[] = [];
      let itemMatch = LIST_ITEM.exec(lines[i]);
      while (itemMatch) {
        const itemKey = `b${key}-i${items.length}`;
        items.push(<li key={itemKey}>{renderInline(itemMatch[1], itemKey)}</li>);
        i += 1;
        itemMatch = i < lines.length ? LIST_ITEM.exec(lines[i]) : null;
      }
      blocks.push(<ul key={`b${key}`} className="md-list">{items}</ul>);
      key += 1;
      continue;
    }

    // Paragraph: consecutive non-blank lines that don't begin a heading or list. Soft-wrapped
    // lines are joined with a space.
    const paraLines: string[] = [];
    while (
      i < lines.length &&
      lines[i].trim() !== "" &&
      !HEADING.test(lines[i]) &&
      !LIST_ITEM.test(lines[i])
    ) {
      paraLines.push(lines[i].trim());
      i += 1;
    }
    const blockKey = `b${key}`;
    blocks.push(
      <p key={blockKey} className="md-paragraph">
        {renderInline(paraLines.join(" "), blockKey)}
      </p>
    );
    key += 1;
  }
  return blocks;
}
