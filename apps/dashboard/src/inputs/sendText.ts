import { parseRecipientValue } from "./messageRecipients";
import type { CerebralBridge } from "../bridge/cerebralBridge";
import type { InputForm, InputValues } from "./inputForm";

/**
 * `send-text` — the only action that speaks to another person, and the last of phase 4.
 *
 * **It never runs one-click.** Every other external write here takes the user-authored exemption,
 * because a calendar event can be edited, a ticket closed, a playlist deleted. A message lands on
 * someone else's device and cannot be unsent, so `messages.send` is `confirm_external_write`
 * outright: the form's success path is *"needs your confirmation"*, not *"sent"*.
 *
 * The confirmation shows the recipient, the group size when there is one, and the **full message
 * body** — hiding it would blank the one thing worth re-reading before it leaves.
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

      // The EXPECTED path. Reporting "sent" here would be the most consequential lie this surface
      // could tell: nothing has left the machine until the confirmation is approved.
      if (result.awaitingConfirmation) {
        return { message: `Confirm to send to ${result.targetName}.` };
      }
      return { message: `Sent to ${result.targetName}.` };
    }
  };
}
