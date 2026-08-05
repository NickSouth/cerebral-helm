/**
 * The Picker archetype (docs/quick-actions/PLAN.md, phase 5): a filter field, a list of results
 * from a provider, and one action on selection.
 *
 * **Not a distinct surface.** A picker renders in the Input region alongside the forms, because a
 * picker's result almost always opens something external and nothing needs to persist. What it is
 * not is a `combobox` field on a one-field form: a combobox *chooses a value* for a submit that
 * happens later, and a picker's row **is** the submit. Modelling one as the other would put a Go
 * button under a list whose rows already do the thing.
 *
 * Deliberately a TypeScript shape rather than a contract, for the same reason as
 * {@link ./inputForm.ts}: a picker is authored here, in code, per action. Nothing outside this
 * codebase composes one.
 */

import type { InputSubmitOutcome } from "./inputForm";

/** One row. `id` is both the React key and what {@link Picker.choose} receives back. */
export interface PickerResult {
  readonly id: string;
  /** The primary line — what the user is scanning for. */
  readonly label: string;
  /** A secondary line: where the thing lives, or why it matched. */
  readonly detail?: string;
  /** A short trailing note (a date, a count). Never load-bearing — it can be absent. */
  readonly meta?: string;
}

/**
 * Something the picker needs to *say* rather than list — and, where there is one, the single step
 * that would fix it.
 *
 * It exists because the honest answer to "no results" is sometimes not "there is nothing" but
 * "this surface cannot see everything yet", and those must never look the same. A notice with no
 * action is a plain statement; one with an action offers the remedy in place rather than sending
 * the user to a settings panel to guess.
 */
export interface PickerNotice {
  readonly message: string;
  readonly action?: {
    readonly label: string;
    /** Performs the remedy and returns what to say afterwards. */
    run(): Promise<InputSubmitOutcome>;
  };
}

export interface PickerOutcome {
  readonly results: readonly PickerResult[];
  readonly notice?: PickerNotice;
}

/**
 * What choosing a row did: finished, or moved to another stage.
 *
 * A picker returning **another picker** is how `take-notes` is two stages (course, then note)
 * without a stage mechanism: each stage is an ordinary picker, and the region keeps a stack so
 * Back is generic rather than something each picker implements. A stage is not a different kind of
 * thing from a picker — it is a picker — so nothing about the surface had to grow.
 */
export type PickerChoice = InputSubmitOutcome | { readonly next: Picker };

/** Whether a choice moved to another stage rather than finishing. */
export function isPickerStage(choice: PickerChoice): choice is { readonly next: Picker } {
  return "next" in choice;
}

export interface Picker {
  /** The quick-action id this picker belongs to. */
  readonly actionId: string;
  readonly title: string;
  readonly placeholder?: string;
  /** What to say when a search legitimately matched nothing. */
  readonly emptyLabel: string;
  /**
   * Results for a query, including the empty query the picker opens with.
   *
   * Asynchronous on purpose even where a source is already in memory: a picker over a remote list
   * and a picker over a local one should differ in latency, not in shape.
   */
  search(query: string): Promise<PickerOutcome>;
  /**
   * Acts on a chosen row, and is given the **current query** because some rows are about what was
   * typed rather than about a result — `+ New note “Lecture 3”` names the note being created.
   *
   * A terminal outcome is announced on the status line exactly as a form's is; a `{ next }` moves
   * to another stage.
   */
  choose(result: PickerResult, query: string): Promise<PickerChoice>;
}

/**
 * How long typing settles before a picker re-searches, in milliseconds.
 *
 * Short enough to feel immediate, long enough that a remote source is not asked once per
 * keystroke. A picker whose source is purely local can ignore it — the delay costs nothing there,
 * and one timing rule is easier to reason about than a per-picker knob.
 */
export const PICKER_DEBOUNCE_MS = 180;
