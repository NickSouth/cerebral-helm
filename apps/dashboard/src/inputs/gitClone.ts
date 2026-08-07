import type { CerebralBridge } from "../bridge/cerebralBridge";
import type { InputForm, InputValues } from "./inputForm";

/**
 * `git-clone` — a repository URL and, optionally, where to put it (quick actions phase 4).
 *
 * **Location is the parent, not the destination.** You pick an existing folder and the clone lands
 * in `<location>/<repository name>` — the way Xcode and GitHub Desktop do it, and the only sensible
 * reading for a native open panel, which selects folders that already exist while a clone target
 * must not. Leaving it blank puts the clone at the top of the projects folder.
 *
 * The **location field carries no authority**. Whatever is typed or picked, the host resolves it
 * inside the projects root and re-checks containment after standardizing the path, so a `..` cannot
 * place a clone elsewhere. That is why the field can exist at all: the form is a convenience, not
 * the boundary. The same reasoning is why the `clone <url>` text grammar deliberately has no
 * location argument — a palette command should not be able to choose a destination even in
 * principle.
 *
 * Nothing here validates the URL beyond "not blank". Scheme, host and embedded credentials are the
 * adapter's checks, and duplicating them in the web layer would mean two rules that can disagree.
 */

/** The folder name the clone will land in, derived from the URL. Blank when it can't be read. */
export function derivedFolderName(repositoryUrl: string): string {
  const trimmed = repositoryUrl.trim().replace(/\/+$/, "");
  if (trimmed.length === 0) {
    return "";
  }
  const last = trimmed.split("/").pop() ?? "";
  return last.replace(/\.git$/, "");
}

/**
 * Joins the chosen parent location and the repository's own name into the folder the tool receives.
 *
 * Computed at submit time rather than when the location is picked, so editing the URL afterwards
 * cannot leave a stale repository name baked into the destination.
 *
 * With **no** location it returns `undefined` rather than the derived name — the host derives the
 * same thing, and sending it from here would put the naming rule in two places that could disagree.
 * The web layer only ever contributes the part the host cannot know: where the user pointed.
 */
export function resolveCloneDirectory(location: string, repositoryUrl: string): string | undefined {
  const parent = location.trim().replace(/^\/+|\/+$/g, "");
  if (parent.length === 0) {
    return undefined;
  }
  const name = derivedFolderName(repositoryUrl);
  return name.length > 0 ? `${parent}/${name}` : parent;
}

export function gitCloneForm(bridge: CerebralBridge): InputForm {
  return {
    actionId: "git-clone",
    title: "Clone repo",
    submitLabel: "Clone",
    fields: [
      {
        name: "repositoryUrl",
        label: "Repository",
        kind: "text",
        required: true,
        placeholder: "https://github.com/owner/repo",
        hint: "https only. A URL with a token in it is refused, not logged."
      },
      {
        name: "location",
        label: "Location",
        kind: "folderPicker",
        placeholder: "Projects",
        hint: "The folder to put it in. The repo gets its own folder inside this one."
      }
    ],
    async submit(values: InputValues) {
      const repositoryUrl = values.repositoryUrl.trim();
      const result = await bridge.cloneRepository({
        repositoryUrl,
        directory: resolveCloneDirectory(values.location ?? "", repositoryUrl)
      });

      // Never report "cloned" for something still waiting on the user's approval.
      if (result.awaitingConfirmation) {
        return { message: `Cloning ${repositoryUrl} needs your confirmation first.` };
      }
      return { message: `Cloned into ${result.clonedPath}.` };
    }
  };
}
