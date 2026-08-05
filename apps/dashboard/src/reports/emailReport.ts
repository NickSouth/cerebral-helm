import type { UnreadMailItem, UnreadMailResult } from "../bridge/cerebralBridge";
import { type UnreadFacts, unreadLabel, unreadValue } from "./unreadCount";
import {
  REPORT_DOCUMENT_SCHEMA_VERSION,
  type ReportBlock,
  type ReportDocument,
  type ReportListItem
} from "./reportDocument";

/**
 * `email-report` — the last of the 26 slots (Gmail integration, 2026-08-04).
 *
 * The shape is the owner's: the most recent unread messages by **subject and byline**, each one a
 * link to that message, with the **unread count below** covering everything the list did not show.
 * Capped at five, because a report is something you read at a glance — past that the number is the
 * useful thing, not the rows.
 *
 * **Every link is an action reference, never a URL.** Each row carries the message's RFC 5322
 * `Message-ID` as a param to `open-mail`, and the `mail.open` tool builds the mail.google.com
 * address host-side. That is the rule the report format has had since phase 2 and it earns itself
 * here: these rows describe real email, and a composed document must never be able to point the
 * browser somewhere of its own choosing.
 *
 * **Gmail cannot be permalinked.** Its web UI addresses a message by an opaque per-account id the
 * API never returns, so the link resolves through `#search/rfc822msgid:` — Gmail filtered to
 * exactly that one message. One view from the message rather than inside it; the honest best.
 */

export const EMAIL_REPORT_ID = "email-report";

/** How many messages the report lists before the count takes over (owner decision). */
export const MAX_LISTED = 5;

/** A short local time — the same treatment the schedule uses, for the same reason. */
export function formatReceived(iso: string | null | undefined): string | undefined {
  if (!iso) {
    return undefined;
  }
  const when = new Date(iso);
  if (Number.isNaN(when.getTime())) {
    return undefined;
  }
  const today = new Date();
  const sameDay =
    when.getFullYear() === today.getFullYear() &&
    when.getMonth() === today.getMonth() &&
    when.getDate() === today.getDate();
  // Today's mail reads as a time; older mail as a date. A bare "09:00" on something from Tuesday
  // would look like it just arrived.
  return sameDay
    ? when.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" })
    : when.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

/**
 * One row: the subject leads because it is what you are scanning for, with the sender as its
 * byline. A message whose sender omitted a `Message-ID` renders as plain text rather than a link
 * that could not resolve — a dead link is worse than an honest non-link.
 */
export function messageItem(message: UnreadMailItem): ReportListItem {
  return {
    text: `${message.subject} — ${message.byline}`,
    meta: formatReceived(message.receivedAt),
    reportAction: message.messageId
      ? { action: "open-mail", params: { messageId: message.messageId } }
      : undefined
  };
}

/**
 * The count line, below the list.
 *
 * It reports the **total** unread, not the remainder, and says how many are shown — "12 unread in
 * Primary · showing the 5 most recent" answers both questions at once, where "7 more" would leave
 * the reader doing arithmetic to learn the thing they actually wanted.
 */
export function countBlock(facts: UnreadFacts | null, listed: number): ReportBlock | null {
  if (facts === null) {
    return null;
  }
  return {
    blockKind: "count",
    value: unreadValue(facts),
    label: unreadLabel(facts, listed),
    // The count opens the inbox, exactly as it does in the daily brief.
    reportAction: { action: "open-mail" }
  };
}

/**
 * What "nothing unread" means, which depends on what was counted.
 *
 * Naming Primary matters most in exactly this state: an inbox holding a hundred unread promotions
 * is not "clear", and saying so flatly would be the report's least believable moment. "Nothing
 * unread in Primary" is both true and the reason the reader is not being shown a wall of mail.
 */
function clearInboxText(facts: UnreadFacts | null): string {
  return facts?.scope === "primary"
    ? "Nothing unread in Primary — open your inbox"
    : "Nothing unread — open your inbox";
}

export interface EmailReportSnapshot {
  readonly mail: UnreadMailResult | null;
  /** The live channel's count, which is authoritative for "how many" — the list is capped and
   *  cannot answer it. Null when the channel has not measured one. */
  readonly unread: UnreadFacts | null;
  readonly loading: boolean;
}

export function composeEmailReport(snapshot: EmailReportSnapshot): ReportDocument {
  const document = (blocks: ReportBlock[]): ReportDocument => ({
    schemaVersion: REPORT_DOCUMENT_SCHEMA_VERSION,
    reportId: EMAIL_REPORT_ID,
    // Re-readable: the mail moved on since it was fetched, which is exactly when you want it again.
    refreshable: true,
    blocks
  });

  if (snapshot.loading && !snapshot.mail) {
    return document([{ blockKind: "empty", text: "Reading your inbox…" }]);
  }

  const mail = snapshot.mail;
  if (!mail || mail.state === "not-connected") {
    return document([
      { blockKind: "empty", text: "Gmail isn’t connected yet — Settings → Setup." }
    ]);
  }
  if (mail.state !== "ready") {
    // Reconnect and a provider fault are different remedies, and the reason says which.
    return document([
      {
        blockKind: "empty",
        text: mail.reason ?? "Your inbox couldn’t be read right now."
      }
    ]);
  }

  const listed = mail.messages.slice(0, MAX_LISTED);

  if (listed.length === 0) {
    // Caught up. Said in words with a way through to the inbox, rather than as a "0" over an empty
    // list: a bare zero next to "nothing unread" says the same thing twice, and the one thing the
    // reader might still want — to go and look anyway — would be missing.
    return document([
      {
        blockKind: "line",
        text: clearInboxText(snapshot.unread),
        lineEmphasis: "muted",
        reportAction: { action: "open-mail" }
      }
    ]);
  }

  const blocks: ReportBlock[] = [
    { blockKind: "list", listItems: listed.map(messageItem) }
  ];

  // The count comes from the live channel where there is one, because the list is capped: counting
  // the rows would report "5 unread" for an inbox holding fifty. With no channel reading, the rows
  // on screen are all that is known — and they are shown, not extrapolated from.
  const count = countBlock(
    snapshot.unread ?? { count: listed.length, capped: false, scope: "inbox" },
    listed.length
  );
  if (count) {
    blocks.push(count);
  }
  return document(blocks);
}
