import type { CerebralBridge, NoteListItem, NoteSearchHit } from "../bridge/cerebralBridge";
import { submitNoteOpen } from "../shell/noteOpen";
import type { Picker, PickerNotice, PickerOutcome, PickerResult } from "./picker";
import type { InputSubmitOutcome } from "./inputForm";

/**
 * `search-notes` — the first Picker (quick actions phase 5). Find a note, open it in Obsidian.
 *
 * **Two sources, merged, because neither one is the library.** `listNotes` walks the Markdown
 * files themselves, so it sees every note including ones authored in Obsidian — but it only knows
 * titles and folders. `searchNotes` reads the derived index, so it can match note *bodies* — but
 * the index only knows what CerebralHelm captured. Using either alone would be quietly wrong in a
 * different direction: titles-only would miss a note whose body has the word, and index-only would
 * miss a vault written by hand.
 *
 * So titles and folders are filtered from the file listing, full text comes from the index, and
 * the two merge on **path** — the one identity both sources agree on. `noteId` could not do this
 * job: a note written outside CerebralHelm has no frontmatter id at all.
 *
 * **The stale index is stated, never hidden.** When a query finds nothing in the index but the
 * library is not empty, the picker says that full text covers indexed notes only and offers the
 * rebuild in place. "No matches" and "this cannot see your notes yet" are different facts, and a
 * surface that renders them identically teaches the user to distrust it.
 *
 * Opening goes through the bus like every other action: the row submits `notes-open <path>` and
 * reports what came back. The path is the one the host reported — the web layer never learns an
 * absolute path, and so cannot ask for one outside the knowledge root.
 */

/** How many notes the empty query shows: the most recently changed, not the whole vault. */
export const RECENT_NOTE_COUNT = 12;

/** How many merged results a query renders before the list is cut. */
export const MATCH_LIMIT = 25;

/** A note as the picker renders it, from either source. */
interface MergedNote {
  readonly path: string;
  readonly title: string;
  readonly folder: string;
  readonly updated: string | null;
  /** Present only when the index matched this note's text. */
  readonly excerpt?: string;
}

/** Whether a listing entry matches typed text by title or by the folder it lives in. */
export function matchesText(note: NoteListItem, needle: string): boolean {
  const lowered = needle.toLowerCase();
  return (
    note.title.toLowerCase().includes(lowered) || note.folder.toLowerCase().includes(lowered)
  );
}

/** The folder a search hit lives in, derived from its path — the index reports no folder field. */
export function folderOf(path: string): string {
  const cut = path.lastIndexOf("/");
  return cut === -1 ? "" : path.slice(0, cut);
}

/**
 * Merges the two sources on path, listing entries first.
 *
 * Listing entries lead because they carry the richer display (a real folder and a change date) and
 * because the empty query is a "most recent" view; a full-text-only hit is appended with what the
 * index knows. A note found by *both* keeps its listing display and gains the excerpt, so a body
 * match can say why it matched without losing where it lives.
 */
export function mergeNotes(
  listed: readonly NoteListItem[],
  hits: readonly NoteSearchHit[],
  hitPaths: ReadonlyMap<string, string>
): readonly MergedNote[] {
  const merged: MergedNote[] = listed.map((note) => ({
    path: note.path,
    title: note.title,
    folder: note.folder,
    updated: note.updated,
    excerpt: hitPaths.get(note.path)
  }));
  const seen = new Set(merged.map((note) => note.path));
  for (const hit of hits) {
    const path = hit.path;
    // A hit with no path cannot be opened, so it is not a result. The index is derived state and
    // can lag the files; a row that fails on click is worse than a row that never appears.
    if (!path || seen.has(path)) {
      continue;
    }
    seen.add(path);
    merged.push({
      path,
      title: hit.title,
      folder: folderOf(path),
      updated: null,
      excerpt: hit.excerpt
    });
  }
  return merged;
}

/** Renders a merged note as a row: title, then why-it-matched or where-it-lives, then its date. */
export function toResult(note: MergedNote): PickerResult {
  return {
    id: note.path,
    label: note.title,
    detail: note.excerpt || note.folder || undefined,
    meta: note.updated ? formatUpdated(note.updated) : undefined
  };
}

/** A short, local date. Anything unparseable renders as nothing rather than "Invalid Date". */
export function formatUpdated(iso: string): string | undefined {
  const when = new Date(iso);
  if (Number.isNaN(when.getTime())) {
    return undefined;
  }
  return when.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

export function searchNotesPicker(bridge: CerebralBridge): Picker {
  return {
    actionId: "search-notes",
    title: "Search notes",
    placeholder: "Title, folder, or anything in the text",
    emptyLabel: "No notes match that.",

    async search(query: string): Promise<PickerOutcome> {
      const needle = query.trim();
      // The listing is re-read per search rather than cached for the life of the picker: a note
      // captured a moment ago should be findable now, and the read is local.
      const library = await bridge.listNotes().catch(() => null);
      if (!library || !library.available) {
        return {
          results: [],
          notice: {
            message:
              "Your knowledge root couldn’t be read. Check where it points under Settings → Setup."
          }
        };
      }

      if (needle.length === 0) {
        // The opening view: most recently changed first, which is the order `listNotes` returns.
        const recent = library.notes.slice(0, RECENT_NOTE_COUNT);
        return {
          results: recent.map((note) =>
            toResult({
              path: note.path,
              title: note.title,
              folder: note.folder,
              updated: note.updated
            })
          )
        };
      }

      const listed = library.notes.filter((note) => matchesText(note, needle));
      // A failed index read is not a failed search — the title matches still stand, and the
      // notice below already covers "full text saw nothing".
      const found = await bridge.searchNotes({ text: needle }).catch(() => ({ results: [] }));
      const hits = found.results;
      const hitPaths = new Map(
        hits.filter((hit) => hit.path).map((hit) => [hit.path as string, hit.excerpt])
      );
      const merged = mergeNotes(listed, hits, hitPaths).slice(0, MATCH_LIMIT);

      return {
        results: merged.map(toResult),
        notice: staleIndexNotice(bridge, hits.length, library.total)
      };
    },

    async choose(result: PickerResult): Promise<InputSubmitOutcome> {
      const receipt = await submitNoteOpen(bridge, result.id);
      if (!receipt.accepted) {
        return { message: `I couldn’t open “${result.label}” — the command wasn’t accepted.`, failed: true };
      }
      // Reports that the open was DISPATCHED, never that Obsidian is now showing the note: the
      // receipt says the command was accepted and nothing more. Whether it landed in Obsidian or
      // in Finder is decided on the host, after this returns.
      return { message: `Opening “${result.label}”.` };
    }
  };
}

/**
 * The rebuild offer, shown only when a stale index is actually a plausible explanation: the query
 * found nothing in the index, and the library is not empty.
 *
 * Not shown when the index did match — full text demonstrably works — and not shown for an empty
 * library, where the honest answer is that there are no notes yet, not that something needs
 * rebuilding.
 */
export function staleIndexNotice(
  bridge: CerebralBridge,
  hitCount: number,
  libraryTotal: number
): PickerNotice | undefined {
  if (hitCount > 0 || libraryTotal === 0) {
    return undefined;
  }
  return {
    message:
      "Full-text search only covers notes CerebralHelm has indexed — notes written in Obsidian need a rebuild.",
    action: {
      label: "Rebuild index",
      async run(): Promise<InputSubmitOutcome> {
        const result = await bridge.rebuildKnowledgeIndex();
        if (!result.rebuilt) {
          return { message: "There’s no knowledge index to rebuild here.", failed: true };
        }
        return { message: `Indexed ${result.noteCount} notes. Search again.` };
      }
    }
  };
}
