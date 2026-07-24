import { postShellControl } from "./shellControl";

/**
 * Ask the native shell to open a project's expandable detail window (NIC-129).
 *
 * Opening a native window is a Mac-only shell concern, so this goes through the private
 * `shellControl` channel (like `openSettings` / `openWindowNavigator`), not the versioned
 * command bus — there is no command result to await; the window's lifecycle is owned by the
 * native `WindowCoordinator`, which reads the project's `PROJECT.md` from `path`. In a plain
 * browser preview there is no native channel, so this is a no-op and returns false.
 */
export function submitOpenProjectDetail(projectPath: string): boolean {
  return postShellControl("openProjectDetail", { path: projectPath });
}

/**
 * Persist a new `importance` for a project (NIC-129) — the detail window's priority stepper.
 * The native `WindowCoordinator` writes it into the project's `PROJECT.md` frontmatter and the
 * widget reorders on its next scan. No-op (returns false) in a plain browser preview.
 */
export function submitSetProjectImportance(projectPath: string, importance: number): boolean {
  return postShellControl("setProjectImportance", { path: projectPath, importance });
}
