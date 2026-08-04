/**
 * The Input archetype's field schema (docs/quick-actions/PLAN.md): an Input is
 * `{title, fields[], submitAction}`.
 *
 * Deliberately **not** a contract, unlike `ReportDocument`. That one is a schema because it is
 * the port a model will later write to — the whole point is that something outside this codebase
 * produces one. A form is authored here, in code, per action; nothing external composes it. The
 * repo's precedent for a shape that stays inside the dashboard is a documented TypeScript type
 * (`widgets/widgetData.ts`), and that is what this is. If a model ever proposes a pre-filled form,
 * that is the moment this becomes a schema.
 *
 * **Mode-aware defaults, not per-slot parameters**: an action appearing in several modes with a
 * different default reads the active mode when its form is built, so there is one id and one
 * registration. Do not add a per-slot parameter mechanism until something actually requires one.
 */

/**
 * The planned field kinds. `combobox` is typeahead over a list too long to scan — it arrived with
 * `send-text`, where the list is an address book. It was deliberately NOT used for Linear's ten
 * labels: typeahead over a short list is worse than a dropdown, not better.
 *
 * `folderPicker` is the one kind needing a **native open-panel round trip**, so it is the one kind
 * that can be unavailable at runtime rather than merely undrawn: a host without a window server
 * has no Finder to open. It degrades to a plain text box in that case, so the field still works
 * where the panel does not.
 */
export type InputFieldKind =
  | "text"
  | "textarea"
  | "select"
  | "multiSelect"
  | "number"
  | "combobox"
  | "datetimeRange"
  | "folderPicker";

/** Kinds the renderer can currently draw. */
export const RENDERABLE_FIELD_KINDS: ReadonlySet<InputFieldKind> = new Set<InputFieldKind>([
  "text",
  "textarea",
  "select",
  "multiSelect",
  "combobox",
  "number",
  "datetimeRange",
  "folderPicker"
]);

/**
 * How a `multiSelect` packs several chosen ids into the one string its slot in `InputValues` holds.
 *
 * The values map is a flat `Record<string, string>` by design, so a multi-value field encodes
 * rather than widening the type — a change that would ripple through seeding, validation and every
 * action's submit for the sake of one field kind. A newline is the separator because no option id
 * or label can contain one, which a comma cannot promise.
 */
export const MULTI_VALUE_SEPARATOR = "\n";

/** The chosen values of a `multiSelect`, in the order they were packed. */
export function parseMultiValue(packed: string | undefined): readonly string[] {
  return (packed ?? "").split(MULTI_VALUE_SEPARATOR).filter((part) => part.length > 0);
}

/** Packs chosen values back into the single string the field's slot holds. */
export function formatMultiValue(values: readonly string[]): string {
  return values.filter((value) => value.length > 0).join(MULTI_VALUE_SEPARATOR);
}

/**
 * Where a `select`/`combobox` gets its options. A static list, or a **provider id** resolved at
 * render time — one mechanism that will serve calendars here, and contacts, Linear projects and
 * Canvas courses later.
 *
 * A provider that fails or is unauthorized yields no options, and the field says so rather than
 * rendering an empty dropdown that looks like the user has no calendars.
 */
export type InputOptionProvider =
  | "calendars"
  | "linearTeams"
  | "linearProjects"
  | "linearLabels"
  | "sportsEvents"
  | "messageRecipients";

export type InputOptionSource =
  | { readonly kind: "static"; readonly options: readonly InputSelectOption[] }
  | { readonly kind: "provider"; readonly provider: InputOptionProvider };

export interface InputSelectOption {
  readonly value: string;
  readonly label: string;
}

export interface InputField {
  /** Key this field's value lands under in the submitted values object. */
  readonly name: string;
  readonly label: string;
  readonly kind: InputFieldKind;
  readonly placeholder?: string;
  /** Seeds the control. A mode-aware default is computed when the form is built. */
  readonly initialValue?: string;
  /** A blank value blocks submission. */
  readonly required?: boolean;
  /** `select` and `combobox` options: a static list, or a provider resolved at render time. */
  readonly source?: InputOptionSource;
  /**
   * Label for a `select`'s blank option — the "choose nothing in particular" choice, which only
   * some fields actually have (a calendar has a system default; a mode does not). Omit it and no
   * blank option is offered, so a field where every choice is real cannot be left unanswered.
   */
  readonly emptyOptionLabel?: string;
  /**
   * The name of another field whose value **scopes** this one's options — a Linear project list
   * narrowed to the chosen team.
   *
   * It exists because the scoping is real, not cosmetic: a project belongs to exactly one team, and
   * offering one from another team would produce a write Linear rejects. A workspace with a single
   * team makes this invisible, which is precisely why it has to be built rather than discovered
   * later — the wrong behaviour would be silent.
   */
  readonly scopedBy?: string;
  /**
   * The most options a `multiSelect` will accept. At the cap the unchosen boxes disable rather
   * than silently refusing a click — a control that ignores you is worse than one that shows it
   * is full.
   */
  readonly maxSelected?: number;
  /**
   * `datetimeRange` writes two values: this field's `name` holds the start, and `endName` holds
   * the end. One field rather than two because a range is one idea, and the renderer can then
   * keep the end consistent with the start on its own.
   */
  readonly endName?: string;
  /** Seeds the end of a `datetimeRange`. */
  readonly initialEndValue?: string;
  /** Extra guidance under the control. */
  readonly hint?: string;
}

export type InputValues = Readonly<Record<string, string>>;

/** What a submit produced, reported honestly on the status line — never fabricated. */
export interface InputSubmitOutcome {
  readonly message: string;
  readonly failed?: boolean;
}

export interface InputForm {
  /** The quick-action id this form belongs to. */
  readonly actionId: string;
  readonly title: string;
  readonly submitLabel: string;
  readonly fields: readonly InputField[];
  /**
   * Performs the action. It receives only the collected values — the form never reaches for
   * ambient state at submit time, so what the user saw is exactly what is sent.
   */
  submit(values: InputValues): Promise<InputSubmitOutcome>;
}

/** The fields the renderer can actually draw, in order. */
export function renderableFields(form: InputForm): readonly InputField[] {
  return form.fields.filter((field) => RENDERABLE_FIELD_KINDS.has(field.kind));
}

/** Every required field that is still blank — the reason a submit is blocked. */
export function missingRequired(form: InputForm, values: InputValues): readonly InputField[] {
  return renderableFields(form).filter((field) => {
    if (!field.required) {
      return false;
    }
    const blank = (name: string) => (values[name] ?? "").trim().length === 0;
    // A range needs both halves — a start with no end is not a filled-in range.
    return blank(field.name) || (field.endName !== undefined && blank(field.endName));
  });
}

/** Seeds the value map from the form's declared initial values, including a range's end. */
export function initialValues(form: InputForm): InputValues {
  const seeded: Record<string, string> = {};
  for (const field of renderableFields(form)) {
    seeded[field.name] = field.initialValue ?? "";
    if (field.endName) {
      seeded[field.endName] = field.initialEndValue ?? "";
    }
  }
  return seeded;
}
