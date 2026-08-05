import type { MailChannel } from "../bridge/cerebralBridge";

/**
 * How the unread count is worded — shared by the daily brief and the email report so the two can
 * never describe the same number differently.
 *
 * The count is **Primary-only** wherever the account uses Gmail's inbox categories: promotions,
 * social and updates are excluded, because they are the bulk of an inbox and almost none of its
 * meaning. That is a real narrowing of what "unread" means, so the label says so rather than
 * letting the reader assume it covers everything.
 */

/** What the host actually measured. */
export interface UnreadFacts {
  readonly count: number;
  /** There are **at least** `count` — counting stopped at a ceiling. */
  readonly capped: boolean;
  readonly scope: "primary" | "inbox";
}

/** The facts from the live channel, or null when nothing was measured. A count is only ever
 *  rendered from a measurement — "not connected" must never render as zero. */
export function unreadFacts(mail: MailChannel | null | undefined): UnreadFacts | null {
  if (!mail || mail.state !== "ready" || mail.unread === null || mail.unread === undefined) {
    return null;
  }
  return {
    count: mail.unread,
    capped: mail.unreadCapped === true,
    // Absent means the host did not say; the whole inbox is the safer assumption, since it makes
    // no promise about filtering that might not have happened.
    scope: mail.unreadScope === "primary" ? "primary" : "inbox"
  };
}

/** The number as displayed: "12", or "100+" when the count hit its ceiling. */
export function unreadValue(facts: UnreadFacts): string {
  return facts.capped ? `${facts.count}+` : String(facts.count);
}

/**
 * The label beneath the number.
 *
 * `listed` — how many rows the surface is showing — turns it into the email report's variant,
 * which answers "how many are there?" and "why am I seeing five?" in one line. The daily brief,
 * which lists nothing, omits it.
 */
export function unreadLabel(facts: UnreadFacts, listed?: number): string {
  const scope = facts.scope === "primary" ? "unread in Primary" : "unread";
  if (listed !== undefined && (facts.capped || facts.count > listed)) {
    return `${scope} · showing the ${listed} most recent`;
  }
  if (facts.scope === "primary") {
    return scope;
  }
  return facts.count === 1 ? "unread email" : "unread emails";
}
