import type { CerebralBridge } from "../bridge/cerebralBridge";
import type { InputForm, InputValues } from "./inputForm";

/**
 * `create-project` — a new project folder under the projects root, with its `PROJECT.md`
 * descriptor (quick actions phase 4).
 *
 * **A project folder is a container, not a repository.** The Projects widget reads projects at
 * depth 1 and the repos live one level inside them, so this creates a folder and nothing else —
 * no `git init`, which would make it a different shape from every project already listed. Putting
 * a repo in it is what `git-clone`'s location picker is for, and the two actions compose.
 *
 * **Location reuses the folder picker** from `git-clone` with the same semantics: it is the
 * parent, the project gets its own folder inside it, and the host re-checks containment whatever
 * arrives. That is why the field can be typed as well as picked.
 */

/** Parses the importance field. Blank leaves it to the host's template default. */
export function parseImportance(value: string | undefined): number | undefined {
  const trimmed = (value ?? "").trim();
  if (trimmed.length === 0) {
    return undefined;
  }
  const parsed = Number(trimmed);
  return Number.isInteger(parsed) && parsed >= 0 && parsed <= 10 ? parsed : undefined;
}

export function createProjectForm(bridge: CerebralBridge): InputForm {
  return {
    actionId: "create-project",
    title: "Create project",
    submitLabel: "Create",
    fields: [
      {
        name: "name",
        label: "Name",
        kind: "text",
        required: true,
        placeholder: "What are you building?"
      },
      {
        name: "location",
        label: "Location",
        kind: "folderPicker",
        placeholder: "Projects",
        hint: "The folder to put it in. The project gets its own folder inside this one."
      },
      {
        name: "summary",
        label: "Summary",
        kind: "text",
        placeholder: "One line, for the dashboard"
      },
      {
        name: "importance",
        label: "Importance",
        kind: "number",
        initialValue: "5",
        hint: "Higher sorts nearer the top of the Projects panel."
      }
    ],
    async submit(values: InputValues) {
      const name = values.name.trim();
      const result = await bridge.scaffoldProject({
        name,
        location: values.location?.trim() || undefined,
        summary: values.summary?.trim() || undefined,
        importance: parseImportance(values.importance)
      });

      // Never report "created" for something still waiting on the user's approval.
      if (result.awaitingConfirmation) {
        return { message: `“${name}” needs your confirmation before it's created.` };
      }
      return { message: `Created ${result.projectPath}.` };
    }
  };
}
