import type { CerebralBridge } from "../bridge/cerebralBridge";
import { parseMultiValue, type InputForm, type InputValues } from "./inputForm";

/**
 * `create-ticket` — the first action backed by a live remote option source (quick actions phase 4).
 *
 * **Team is a field, not an inference.** Linear requires a team on every issue, and this workspace
 * currently has exactly one — which is precisely why the form asks rather than picking: a silent
 * "use the first team" would keep working right up until a second team existed, and then file
 * tickets somewhere they were never meant to go. With one team the dropdown has one entry, which
 * costs a glance and buys correctness.
 *
 * **Project and label are scoped by the team.** Both belong to exactly one team in Linear, so the
 * form narrows them through `scopedBy` rather than offering the whole workspace and letting the API
 * reject the mismatch.
 *
 * **`select`, not `combobox`.** The plan expected this action to introduce typeahead. It does not,
 * because typeahead over one project and ten labels is worse than a dropdown, not better —
 * `combobox` waits for a list that is genuinely long (contacts, for `send-text`).
 *
 * **Labels are multi-select.** A Linear issue routinely carries several — a category and a status —
 * so a single-choice dropdown would send the user to Linear to add the second one. It is the first
 * user of the `multiSelect` field kind.
 */

/** Linear's priority scale, verified against the live API: 0 none, 1 urgent, 2 high, 3 medium, 4 low. */
export const LINEAR_PRIORITIES = [
  { value: "1", label: "Urgent" },
  { value: "2", label: "High" },
  { value: "3", label: "Medium" },
  { value: "4", label: "Low" }
] as const;

/** Parses the priority field. Blank means "leave it unset", which is not the same as "none". */
export function parsePriority(value: string | undefined): number | undefined {
  const trimmed = (value ?? "").trim();
  if (trimmed.length === 0) {
    return undefined;
  }
  const parsed = Number(trimmed);
  return Number.isInteger(parsed) && parsed >= 0 && parsed <= 4 ? parsed : undefined;
}

export function createTicketForm(bridge: CerebralBridge): InputForm {
  return {
    actionId: "create-ticket",
    title: "Create ticket",
    submitLabel: "Create",
    fields: [
      {
        name: "title",
        label: "Title",
        kind: "text",
        required: true,
        placeholder: "What needs doing?"
      },
      {
        name: "teamId",
        label: "Team",
        kind: "select",
        required: true,
        source: { kind: "provider", provider: "linearTeams" },
        hint: "Linear files every issue under a team."
      },
      {
        name: "projectId",
        label: "Project",
        kind: "select",
        source: { kind: "provider", provider: "linearProjects" },
        scopedBy: "teamId",
        emptyOptionLabel: "No project"
      },
      {
        name: "labelIds",
        label: "Labels",
        kind: "multiSelect",
        source: { kind: "provider", provider: "linearLabels" },
        scopedBy: "teamId"
      },
      {
        name: "priority",
        label: "Priority",
        kind: "select",
        source: { kind: "static", options: [...LINEAR_PRIORITIES] },
        emptyOptionLabel: "No priority"
      },
      { name: "description", label: "Description", kind: "textarea", placeholder: "Optional" }
    ],
    async submit(values: InputValues) {
      const title = values.title.trim();
      const result = await bridge.createLinearIssue({
        title,
        description: values.description?.trim() || undefined,
        teamId: values.teamId,
        // The chosen options' LABELS ride along so a confirmation can name the destination in
        // words; an id alone is unreadable in a prompt.
        teamName: values.teamIdLabel || undefined,
        projectId: values.projectId || undefined,
        projectName: values.projectIdLabel || undefined,
        labelIds: parseMultiValue(values.labelIds),
        labelNames: parseMultiValue(values.labelIdsLabel),
        priority: parsePriority(values.priority)
      });

      // Never report "created" for something still waiting on the user's approval.
      if (result.awaitingConfirmation) {
        return { message: `“${title}” needs your confirmation before it's filed.` };
      }
      return { message: `Filed ${result.identifier}: “${title}”.` };
    }
  };
}
