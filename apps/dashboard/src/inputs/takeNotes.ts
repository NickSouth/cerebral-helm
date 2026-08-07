import type { CerebralBridge, CourseFolder, NoteListItem } from "../bridge/cerebralBridge";
import { submitNoteOpen } from "../shell/noteOpen";
import { formatUpdated } from "./searchNotes";
import type { Picker, PickerChoice, PickerOutcome, PickerResult } from "./picker";

/**
 * `take-notes` — the second Picker, and the first two-stage one (quick actions phase 5).
 *
 * Pick a course, then pick one of its notes to open — or type a title and make a new one. Both
 * stages end in Obsidian, which is where the writing actually happens.
 *
 * **A stage is just a picker.** The course stage's `choose` returns the note stage rather than
 * setting a mode flag, so the region's stack handles Back and nothing here implements navigation.
 *
 * **Two sources of courses, and the merge is presentational only.** Canvas knows what you are
 * enrolled in; the vault knows what you have written in. Neither is the list on its own — a course
 * from a finished semester is gone from Canvas and still has your notes, and a reading group was
 * never in Canvas at all. They are matched loosely here on purpose: the folder is derived **on the
 * host** from the course name, so if a match is missed the worst case is two rows that both land
 * in the same folder. Duplicating the host's naming rule in TypeScript to tighten that up would
 * create a second rule that can disagree with the first, which is a real bug in exchange for a
 * cosmetic one.
 *
 * **Nothing is created by browsing.** Choosing a course you have never used shows an empty note
 * list and a `+ New note` row; the folder appears when the first note does.
 */

/** A course as the first stage renders it: from the vault, from Canvas, or both. */
export interface CourseChoice {
  /** What to call it, and what the host derives the folder from. */
  readonly course: string;
  /** Root-relative, when the course already exists on disk. Absent for a Canvas-only course. */
  readonly folder?: string;
  readonly noteCount?: number;
  readonly updated?: string | null;
}

/** The Canvas course rows the dashboard already streams for the School widgets. */
export interface CanvasCourse {
  readonly name: string;
  readonly code?: string;
}

/** The row id prefix that means "make the thing I typed" rather than "open this result". */
export const CREATE_ROW_ID = "__create__";

/** Case- and space-insensitive comparison, so `stat 240` and `STAT  240` are one course. */
export function normalizeCourse(value: string): string {
  return value.trim().toUpperCase().split(/\s+/).join(" ");
}

/**
 * The same, with **all** spacing removed — `CS260` and `CS 260` become one string.
 *
 * Canvas writes course codes both ways, and the host's derivation normalizes the spacing when it
 * names the folder, so without this the same course renders twice on its very first use. It is
 * used only for **whole-value equality**, never for the prefix test below: `STAT 2400` compacts to
 * something that starts with `STAT240`, and a false match would hide a real course.
 */
export function compactCourse(value: string): string {
  return value.toUpperCase().replace(/\s+/g, "");
}

/**
 * Whether a Canvas course is already represented by a folder in the vault.
 *
 * Matched on the code when Canvas gives one, else on the folder name being how the course name
 * begins — which is what the host's own derivation produces. A miss shows the course twice and is
 * harmless; a false match would hide a course, so the prefix test is deliberately narrow.
 */
export function matchesFolder(canvas: CanvasCourse, folderName: string): boolean {
  const folder = normalizeCourse(folderName);
  const compact = compactCourse(folderName);
  if (canvas.code && compactCourse(canvas.code) === compact) {
    return true;
  }
  const name = normalizeCourse(canvas.name);
  return (
    compactCourse(canvas.name) === compact ||
    name.startsWith(`${folder} `) ||
    name.startsWith(`${folder}-`)
  );
}

/**
 * The course list: what is on disk first, then Canvas courses with no notes yet.
 *
 * On-disk courses lead because they are the ones with something to open; a Canvas course you have
 * never written in is an invitation rather than a destination.
 */
export function mergeCourses(
  onDisk: readonly CourseFolder[],
  canvas: readonly CanvasCourse[]
): readonly CourseChoice[] {
  const existing: CourseChoice[] = onDisk.map((folder) => ({
    course: folder.course,
    folder: folder.folder,
    noteCount: folder.noteCount,
    updated: folder.updated
  }));
  const unwritten = canvas
    .filter((course) => !onDisk.some((folder) => matchesFolder(course, folder.course)))
    // Canvas's own short code where it has one: it is what the host would derive anyway, and it is
    // what a course is actually called.
    .map((course) => ({ course: (course.code ?? course.name).trim() }))
    .filter((course) => course.course.length > 0);
  return [...existing, ...unwritten];
}

/** Renders a course row: how many notes, and when it was last written in. */
export function courseResult(choice: CourseChoice): PickerResult {
  const count = choice.noteCount ?? 0;
  return {
    id: choice.course,
    label: choice.course,
    // "No notes yet" is a real state and says so, rather than rendering a blank second line that
    // reads like something failed to load.
    detail: count === 0 ? "No notes yet" : count === 1 ? "1 note" : `${count} notes`,
    meta: choice.updated ? formatUpdated(choice.updated) : undefined
  };
}

/** The `+ New …` row for whatever is currently typed, or nothing when nothing is typed. */
export function createRow(query: string, noun: string): PickerResult | null {
  const typed = query.trim();
  if (typed.length === 0) {
    return null;
  }
  return {
    id: `${CREATE_ROW_ID}${typed}`,
    label: `+ New ${noun} “${typed}”`,
    detail: `Creates ${typed}`
  };
}

export function takeNotesPicker(
  bridge: CerebralBridge,
  canvasCourses: readonly CanvasCourse[]
): Picker {
  return {
    actionId: "take-notes",
    title: "Take notes",
    placeholder: "Which course?",
    emptyLabel: "No courses yet — type a name to start one.",

    async search(query: string): Promise<PickerOutcome> {
      const listed = await bridge.listCourses().catch(() => null);
      if (!listed || !listed.available) {
        return {
          results: [],
          notice: {
            message:
              "Your knowledge root couldn’t be read. Check where it points under Settings → Setup."
          }
        };
      }

      const needle = normalizeCourse(query);
      const merged = mergeCourses(listed.courses, canvasCourses).filter(
        (choice) => needle.length === 0 || normalizeCourse(choice.course).includes(needle)
      );
      const results = merged.map(courseResult);

      // Only offer to create a course that is not already in the list, so `+ New course “STAT 240”`
      // never appears above the STAT 240 that exists — and typing `cs260` does not offer to create
      // a second CS 260 either.
      const typed = compactCourse(query.trim());
      const exact = merged.some((choice) => compactCourse(choice.course) === typed);
      const create = exact ? null : createRow(query, "course");
      return { results: create ? [...results, create] : results };
    },

    async choose(result: PickerResult, query: string): Promise<PickerChoice> {
      if (result.id.startsWith(CREATE_ROW_ID)) {
        // A new course is not created here — nothing is written until a note is. It simply becomes
        // the second stage, which is what "the course exists once you write in it" means.
        return { next: courseNotesPicker(bridge, { course: query.trim() }) };
      }
      const listed = await bridge.listCourses().catch(() => null);
      const folder = listed?.courses.find((entry) => entry.course === result.id);
      return {
        next: courseNotesPicker(bridge, { course: result.id, folder: folder?.folder })
      };
    }
  };
}

/**
 * The second stage: one course's notes, newest first, with a `+ New note` row.
 *
 * The notes come from `listNotes` filtered by folder rather than from a course-specific read —
 * a course note is an ordinary note, so the listing already has them, and a second endpoint would
 * be a second way for the same question to be answered differently.
 */
export function courseNotesPicker(bridge: CerebralBridge, choice: CourseChoice): Picker {
  return {
    actionId: "take-notes",
    title: choice.course,
    placeholder: "Open a note, or type a title for a new one",
    emptyLabel: "No notes in this course yet — type a title to start one.",

    async search(query: string): Promise<PickerOutcome> {
      const results = choice.folder ? await notesIn(bridge, choice.folder, query) : [];
      const create = createRow(query, "note");
      return { results: create ? [...results, create] : results };
    },

    async choose(result: PickerResult, query: string): Promise<PickerChoice> {
      if (!result.id.startsWith(CREATE_ROW_ID)) {
        const receipt = await submitNoteOpen(bridge, result.id);
        if (!receipt.accepted) {
          return {
            message: `I couldn’t open “${result.label}” — the command wasn’t accepted.`,
            failed: true
          };
        }
        return { message: `Opening “${result.label}”.` };
      }

      const title = query.trim();
      const created = await bridge.createCourseNote({ course: choice.course, title });
      // Never report a note as written while its confirmation is pending, and never offer to open
      // a path that does not exist yet.
      if (created.awaitingConfirmation) {
        return { message: `“${title}” needs your confirmation before it's created.` };
      }

      // Open what was just created — the point of the action is to start writing, and Obsidian is
      // where that happens. A failed open never turns into a failed create: the note is on disk
      // either way, and saying otherwise would send the user looking for something that exists.
      const receipt = await submitNoteOpen(bridge, created.path);
      const opening = receipt.accepted ? " Opening it." : " Open it in Obsidian.";
      // `created: false` means a note of that title already existed for today, which is a person
      // returning to what they started rather than a failure — so it opens, and says which it was.
      return {
        message: created.created
          ? `Created “${created.title}” in ${created.course}.${opening}`
          : `“${created.title}” already exists in ${created.course}.${opening}`
      };
    }
  };
}

/** One course's notes, newest first, filtered by what is typed. */
async function notesIn(
  bridge: CerebralBridge,
  folder: string,
  query: string
): Promise<readonly PickerResult[]> {
  const library = await bridge.listNotes().catch(() => null);
  if (!library || !library.available) {
    return [];
  }
  const needle = query.trim().toLowerCase();
  return library.notes
    .filter((note) => note.folder === folder)
    .filter((note) => needle.length === 0 || note.title.toLowerCase().includes(needle))
    .map(noteResult);
}

/** Renders one of a course's notes. The date is the point — a notebook reads chronologically. */
export function noteResult(note: NoteListItem): PickerResult {
  return {
    id: note.path,
    label: note.title,
    meta: note.updated ? formatUpdated(note.updated) : undefined
  };
}
