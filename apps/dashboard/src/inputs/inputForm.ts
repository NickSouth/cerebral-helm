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
 * The seven planned field kinds. `combobox` (typeahead over a long list — contacts, Linear
 * projects) and `folderPicker` (the only kind needing a native open-panel round trip) are declared
 * but not yet rendered; they arrive with the first action that needs them. The renderer skips an
 * unrendered kind rather than drawing a broken control.
 */
export type InputFieldKind =
  | "text"
  | "textarea"
  | "select"
  | "number"
  | "combobox"
  | "datetimeRange"
  | "folderPicker";

/** Kinds the renderer can currently draw. */
export const RENDERABLE_FIELD_KINDS: ReadonlySet<InputFieldKind> = new Set<InputFieldKind>([
  "text",
  "textarea",
  "select",
  "number",
  "datetimeRange"
]);

/**
 * Where a `select`/`combobox` gets its options. A static list, or a **provider id** resolved at
 * render time — one mechanism that will serve calendars here, and contacts, Linear projects and
 * Canvas courses later.
 *
 * A provider that fails or is unauthorized yields no options, and the field says so rather than
 * rendering an empty dropdown that looks like the user has no calendars.
 */
export type InputOptionSource =
  | { readonly kind: "static"; readonly options: readonly InputSelectOption[] }
  | { readonly kind: "provider"; readonly provider: "calendars" };

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
