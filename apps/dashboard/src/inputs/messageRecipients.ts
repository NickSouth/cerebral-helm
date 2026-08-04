import { useEffect, useState } from "react";
import { useBridge } from "../state/BridgeProvider";
import type { ListMessageRecipientsResult, MessageRecipient } from "../bridge/cerebralBridge";

/**
 * The recipient read behind `send-text` (quick actions phase 4).
 *
 * Read once when the form opens, and deliberately not cached across opens: a contact added a
 * moment ago should be findable, and the read is cheap next to the permission prompt behind it.
 */
export interface MessageRecipientsState {
  readonly result: ListMessageRecipientsResult | null;
  readonly loading: boolean;
  readonly failed: boolean;
}

export function useMessageRecipients(enabled: boolean): MessageRecipientsState {
  const bridge = useBridge();
  const [state, setState] = useState<MessageRecipientsState>({
    result: null,
    loading: enabled,
    failed: false
  });

  useEffect(() => {
    if (!enabled) {
      return;
    }
    let cancelled = false;
    void bridge
      .listMessageRecipients()
      .then((result) => {
        if (!cancelled) {
          setState({ result, loading: false, failed: false });
        }
      })
      .catch(() => {
        if (!cancelled) {
          setState({ result: null, loading: false, failed: true });
        }
      });
    return () => {
      cancelled = true;
    };
  }, [bridge, enabled]);

  return state;
}

/**
 * How a recipient reads in the picker.
 *
 * A group says how many people are in it, because that is the fact that changes what sending
 * means. A person shows their handle, because two contacts can share a name and the handle is
 * what actually decides where it goes.
 */
export function recipientLabel(recipient: MessageRecipient): string {
  if (recipient.kind === "chat") {
    return recipient.groupSize
      ? `${recipient.name} · group of ${recipient.groupSize}`
      : `${recipient.name} · thread`;
  }
  return recipient.handle ? `${recipient.name} · ${recipient.handle}` : recipient.name;
}

/** Splits the picker's packed `kind:id` value back into what the tool needs. */
export function parseRecipientValue(
  packed: string | undefined
): { target: string; targetKind: "participant" | "chat" } | null {
  const value = (packed ?? "").trim();
  const separator = value.indexOf(":");
  if (separator <= 0) {
    return null;
  }
  const kind = value.slice(0, separator);
  const target = value.slice(separator + 1);
  if (target.length === 0 || (kind !== "participant" && kind !== "chat")) {
    return null;
  }
  return { target, targetKind: kind };
}
