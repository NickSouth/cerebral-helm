import type { CerebralBridge, CommandReceipt } from "../bridge/cerebralBridge";

/**
 * Open one note in the user's Markdown editor (quick actions phase 5).
 *
 * The same shape as {@link submitYouTubeSearch} and through the same bus — `submitCommand` with
 * the `notes-open <path>` grammar — so the `note.open` tool is planned, policy-checked and logged
 * like every other action rather than reaching the host down a private channel.
 *
 * `path` is **root-relative**, as reported by `listNotes` / `searchNotes`. The web layer never
 * holds an absolute path, so it cannot ask for a file outside the knowledge root; the host
 * resolves the path against the root and refuses anything that lands elsewhere.
 *
 * Being a `local_write` it opens in one click. The receipt only says whether the command was
 * accepted — which surface finally took the note is decided on the host, after this resolves.
 */
export function submitNoteOpen(bridge: CerebralBridge, path: string): Promise<CommandReceipt> {
  return bridge.submitCommand({ rawInput: `notes-open ${path}`, source: "dashboard" });
}
