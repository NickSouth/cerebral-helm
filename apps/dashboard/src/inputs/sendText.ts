import { parseRecipientValue } from "./messageRecipients";
import type { CerebralBridge } from "../bridge/cerebralBridge";
import type { InputForm, InputValues } from "./inputForm";

/**
 * `send-text` — the only action that speaks to another person, and the last of phase 4.
 *
 * **It takes the user-authored exemption — and that is the whole point of the provenance tier**
 * (owner decision, 2026-08-04). Filling in a recipient and a message and pressing Send *is* the
 * confirmation: re-asking would restate what the user just typed, one dialog after another, for
 * the action they perform most. The same call proposed by an **agent** still gates, with the
 * recipient, the group size and the **full message body** disclosed — which is the case the
 * confirmation was ever really for. "Ask before all actions" still re-arms it.
 *
 * The disclosure itself is unchanged and still honest: `reversibility: not_reversible`, because a
 * sent message cannot be recalled. What changed is *who* is shown it.
 *
 * **A new group cannot be assembled.** Messages' scripting dictionary makes `chat` read-only, so
 * the picker offers contacts and *existing* threads. Offering to build a group would be a control
 * that silently could not work.
 */
export function sendTextForm(bridge: CerebralBridge): InputForm {
  return {
    actionId: "send-text",
    title: "Send text",
    submitLabel: "Send",
    fields: [
      {
        name: "recipient",
        label: "To",
        kind: "combobox",
        required: true,
        source: { kind: "provider", provider: "messageRecipients" },
        placeholder: "Search contacts and threads",
        hint: "Existing group threads work; a new group can't be started from here."
      },
      {
        name: "body",
        label: "Message",
        kind: "textarea",
        required: true,
        placeholder: "What do you want to say?"
      }
    ],
    async submit(values: InputValues) {
      const recipient = parseRecipientValue(values.recipient);
      if (!recipient) {
        // Unreachable through the picker, which only ever writes a packed value — but a form that
        // could send to a half-parsed recipient is not one to leave to chance.
        return { message: "Pick who this is going to first.", failed: true };
      }
      const body = values.body.trim();
      const label = values.recipientLabel || recipient.target;
      // The group size travels so the confirmation can say "9 people" — sending to a thread is a
      // materially bigger action than sending to one person.
      const groupMatch = /group of (\d+)/.exec(label);

      const result = await bridge.sendMessage({
        body,
        target: recipient.target,
        targetKind: recipient.targetKind,
        targetName: label.split(" · ")[0],
        groupSize: groupMatch ? Number(groupMatch[1]) : undefined
      });

      // Still handled, and still the truth when it happens: an agent-proposed send, or any send
      // while "ask before all actions" is on, waits on a confirmation. Reporting "sent" for one of
      // those would be the most consequential lie this surface could tell.
      if (result.awaitingConfirmation) {
        return { message: `Confirm to send to ${result.targetName}.` };
      }
      return { message: `Sent to ${result.targetName}.` };
    }
  };
}
