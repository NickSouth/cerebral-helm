import { useEffect, useState } from "react";
import { useInputForm } from "./useInputForm";
import {
  initialValues,
  missingRequired,
  renderableFields,
  type InputField,
  type InputForm,
  type InputOptionSource,
  type InputSelectOption,
  type InputValues
} from "./inputForm";
import { useBridge } from "../state/BridgeProvider";
import { quickActionLabel } from "../shell/quickActionRegistry";
import { useActionStatus } from "../state/ActionStatusProvider";
import { useUiPosture } from "../state/useUiPosture";
import { useInputs } from "../state/InputProvider";

/**
 * The Input region (docs/quick-actions/PLAN.md): the centre panel's lower right — below the
 * consciousness stream, above the quick-action grid.
 *
 * Unlike the Report region this one is a **bordered panel**: it is interactive and needs a hit
 * target, where a report is something you read. A Picker will render here too, with a filter
 * field and a result list above the same footer.
 */
export function InputRegion() {
  const { openInputId, closeInput } = useInputs();
  const { form, loading } = useInputForm(openInputId ?? "");

  if (!openInputId) {
    return null;
  }

  return (
    <section className="input-region" aria-label={`${quickActionLabel(openInputId)} form`}>
      <header className="input-region__head">
        <h2 className="input-region__title">{form?.title ?? quickActionLabel(openInputId)}</h2>
        <button
          type="button"
          className="input-region__close"
          aria-label={`Close the ${quickActionLabel(openInputId)} form`}
          onClick={closeInput}
        >
          ×
        </button>
      </header>

      {loading ? (
        <p className="input-region__pending">Loading…</p>
      ) : form ? (
        // Keyed so switching between two Inputs starts from a clean set of values rather than
        // carrying the previous form's typing across.
        <InputFormBody key={form.actionId} form={form} onDone={closeInput} />
      ) : (
        <p className="input-region__pending">This action isn’t built yet.</p>
      )}
    </section>
  );
}

function InputFormBody({ form, onDone }: { form: InputForm; onDone: () => void }) {
  const { announce } = useActionStatus();
  const { readOnly } = useUiPosture();
  const [values, setValues] = useState<InputValues>(() => initialValues(form));
  const [submitting, setSubmitting] = useState(false);

  const fields = renderableFields(form);
  const missing = missingRequired(form, values);
  const canSubmit = !readOnly && !submitting && missing.length === 0;

  function set(name: string, value: string) {
    setValues((current) => ({ ...current, [name]: value }));
  }

  function onSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (!canSubmit) {
      return;
    }
    setSubmitting(true);
    void form
      .submit(values)
      .then((outcome) => {
        announce(outcome.message, outcome.failed ? "error" : undefined);
        // A failed submit keeps the form open with the user's typing intact — losing what they
        // wrote because a write failed would be the worst possible response to a failure.
        if (!outcome.failed) {
          onDone();
        }
      })
      .catch(() => {
        announce(`${form.title} failed — the bridge did not accept it.`, "error");
      })
      .finally(() => setSubmitting(false));
  }

  return (
    <form className="input-region__form" onSubmit={onSubmit}>
      {fields.map((field) => (
        <FieldView
          key={field.name}
          field={field}
          values={values}
          disabled={readOnly || submitting}
          onChange={set}
        />
      ))}

      <footer className="input-region__footer">
        <button
          type="button"
          className="input-region__cancel"
          disabled={submitting}
          onClick={onDone}
        >
          Cancel
        </button>
        <button
          type="submit"
          className="input-region__submit"
          disabled={!canSubmit}
          // Honest about WHY it is disabled, rather than an inert button with no explanation.
          title={
            readOnly
              ? "Paused while the dashboard is read-only"
              : missing.length > 0
                ? `${missing.map((field) => field.label).join(", ")} required`
                : undefined
          }
        >
          {submitting ? "Working…" : form.submitLabel}
        </button>
      </footer>
    </form>
  );
}

/**
 * Resolves a field's option source. A static list is returned as-is; a provider is fetched once.
 *
 * A provider that fails or is unauthorized yields **no** options and says so, rather than an empty
 * dropdown — "you have no calendars" and "we could not read your calendars" are different facts.
 */
function useOptionSource(source: InputOptionSource | undefined): {
  options: readonly InputSelectOption[];
  unavailable: boolean;
} {
  const bridge = useBridge();
  const [resolved, setResolved] = useState<{
    options: readonly InputSelectOption[];
    unavailable: boolean;
  }>({ options: [], unavailable: false });

  const provider = source?.kind === "provider" ? source.provider : null;

  useEffect(() => {
    if (provider !== "calendars") {
      return;
    }
    let cancelled = false;
    void bridge
      .listCalendars()
      .then((result) => {
        if (cancelled) {
          return;
        }
        setResolved({
          options: result.calendars.map((calendar) => ({
            value: calendar.id,
            label: calendar.title
          })),
          unavailable: !result.authorized
        });
      })
      .catch(() => {
        if (!cancelled) {
          setResolved({ options: [], unavailable: true });
        }
      });
    return () => {
      cancelled = true;
    };
  }, [bridge, provider]);

  if (source?.kind === "static") {
    return { options: source.options, unavailable: false };
  }
  return resolved;
}

function FieldView({
  field,
  values,
  disabled,
  onChange
}: {
  field: InputField;
  values: InputValues;
  disabled: boolean;
  onChange: (name: string, next: string) => void;
}) {
  const id = `input-field-${field.name}`;
  const { options, unavailable } = useOptionSource(field.source);
  const hint = unavailable ? "Your calendars couldn\u2019t be read — this will use the default." : field.hint;
  const describedBy = hint ? `${id}-hint` : undefined;
  const value = values[field.name] ?? "";

  function selectOption(next: string) {
    onChange(field.name, next);
    // The chosen option's LABEL is recorded alongside its value under `<name>Label`, so a submit
    // can name the destination in words. An id alone is unreadable in a confirmation prompt.
    onChange(`${field.name}Label`, options.find((option) => option.value === next)?.label ?? "");
  }

  // A provider's options arrive AFTER the form seeded its initial value, so a preselected id has
  // no matching <option> on first render. Rendering the value only once its option exists makes
  // React apply it when the options land — otherwise the select silently falls back to the first
  // option and the mode-aware default is lost. The stored value is untouched either way.
  const selectedOption = options.find((option) => option.value === value);
  const renderedSelectValue = selectedOption ? value : "";

  // Keep the companion label in step with a value the user never touched (the seeded default),
  // so a confirmation can still name the calendar.
  const storedLabel = values[`${field.name}Label`];
  useEffect(() => {
    if (selectedOption && storedLabel !== selectedOption.label) {
      onChange(`${field.name}Label`, selectedOption.label);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedOption?.value, selectedOption?.label, storedLabel]);

  return (
    <div className="input-field">
      <label className="input-field__label" htmlFor={id}>
        {field.label}
        {field.required ? <span className="input-field__required"> *</span> : null}
      </label>

      {field.kind === "textarea" ? (
        <textarea
          id={id}
          className="input-field__control input-field__control--area"
          value={value}
          rows={3}
          disabled={disabled}
          placeholder={field.placeholder}
          aria-describedby={describedBy}
          onChange={(event) => onChange(field.name, event.target.value)}
        />
      ) : field.kind === "select" ? (
        <select
          id={id}
          className="input-field__control"
          value={renderedSelectValue}
          disabled={disabled}
          aria-describedby={describedBy}
          onChange={(event) => selectOption(event.target.value)}
        >
          {/* A blank option only where "nothing in particular" is a real choice — the honest
              default when the mode maps to no calendar, better than preselecting one the user
              never picked. A field without one still gets a blank placeholder while its stored
              value has no matching option, so the control never shows a choice nobody made. */}
          {field.emptyOptionLabel !== undefined || renderedSelectValue === "" ? (
            <option value="">{field.emptyOptionLabel ?? "Select…"}</option>
          ) : null}
          {options.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </select>
      ) : field.kind === "datetimeRange" ? (
        <div className="input-field__range">
          <input
            id={id}
            className="input-field__control"
            type="datetime-local"
            value={value}
            disabled={disabled}
            aria-label={`${field.label} starts`}
            aria-describedby={describedBy}
            onChange={(event) => {
              onChange(field.name, event.target.value);
              // Dragging the start past the end would submit a backwards range, which the tool
              // rejects. Carrying the end along keeps the control from producing invalid input
              // at all, rather than validating it after the fact.
              const end = field.endName ? values[field.endName] : undefined;
              if (field.endName && end !== undefined && end < event.target.value) {
                onChange(field.endName, event.target.value);
              }
            }}
          />
          <span className="input-field__range-to" aria-hidden="true">
            to
          </span>
          <input
            className="input-field__control"
            type="datetime-local"
            value={field.endName ? (values[field.endName] ?? "") : ""}
            min={value || undefined}
            disabled={disabled}
            aria-label={`${field.label} ends`}
            onChange={(event) => field.endName && onChange(field.endName, event.target.value)}
          />
        </div>
      ) : field.kind === "folderPicker" ? (
        <FolderPickerControl
          id={id}
          field={field}
          value={value}
          disabled={disabled}
          describedBy={describedBy}
          onChange={onChange}
        />
      ) : (
        <input
          id={id}
          className="input-field__control"
          type={field.kind === "number" ? "number" : "text"}
          value={value}
          disabled={disabled}
          placeholder={field.placeholder}
          aria-describedby={describedBy}
          onChange={(event) => onChange(field.name, event.target.value)}
        />
      )}

      {hint ? (
        <p className="input-field__hint" id={describedBy}>
          {hint}
        </p>
      ) : null}
    </div>
  );
}

/**
 * A native folder picker, with the typed box still underneath it.
 *
 * The button is the whole point — but it is the *only* part that can be unavailable, because it
 * needs a window server the browser preview does not have. So the text input is always rendered
 * and always authoritative: the panel writes into it, and where there is no panel the field still
 * works by typing. A button that silently does nothing would be worse than no button.
 *
 * What the panel returns is a **relative** path inside the projects root, because the host resolves
 * and range-checks it there. Nothing here validates the path: the adapter re-checks containment
 * after standardizing whatever finally arrives, and a second rule in the web layer could only
 * disagree with the first.
 */
function FolderPickerControl({
  id,
  field,
  value,
  disabled,
  describedBy,
  onChange
}: {
  id: string;
  field: InputField;
  value: string;
  disabled: boolean;
  describedBy?: string;
  onChange: (name: string, next: string) => void;
}) {
  const bridge = useBridge();
  const [picking, setPicking] = useState(false);
  // `null` until a pick has been attempted: the button renders hopefully rather than needing a
  // probe on mount for a capability most opens never use.
  const [unavailable, setUnavailable] = useState(false);
  const [refused, setRefused] = useState(false);

  async function pick() {
    setPicking(true);
    setRefused(false);
    try {
      const result = await bridge.chooseFolder();
      if (!result.available) {
        setUnavailable(true);
        return;
      }
      if (result.outsideRoot) {
        // Refused, not cancelled — the user did choose something, and deserves to know why it
        // did not take.
        setRefused(true);
        return;
      }
      if (!result.cancelled && result.relativeFolder !== null) {
        onChange(field.name, result.relativeFolder);
      }
    } catch {
      setUnavailable(true);
    } finally {
      setPicking(false);
    }
  }

  return (
    <>
      <div className="input-field__picker">
        <input
          id={id}
          className="input-field__control"
          type="text"
          value={value}
          disabled={disabled}
          placeholder={field.placeholder}
          aria-describedby={describedBy}
          onChange={(event) => onChange(field.name, event.target.value)}
        />
        {unavailable ? null : (
          <button
            type="button"
            className="input-field__picker-button"
            disabled={disabled || picking}
            onClick={() => void pick()}
          >
            {picking ? "Choosing…" : "Choose…"}
          </button>
        )}
      </div>
      {refused ? (
        <p className="input-field__hint input-field__hint--warning">
          That folder is outside your projects folder. Pick one inside it.
        </p>
      ) : null}
    </>
  );
}
