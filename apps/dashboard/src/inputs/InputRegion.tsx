import { useEffect, useRef, useState, type RefObject } from "react";
import { useInputForm } from "./useInputForm";
import { usePicker } from "./usePicker";
import { useLeaveTransition } from "../shell/useLeaveTransition";
import {
  PICKER_DEBOUNCE_MS,
  isPickerStage,
  type Picker,
  type PickerNotice,
  type PickerOutcome,
  type PickerResult
} from "./picker";
import {
  initialValues,
  missingRequired,
  renderableFields,
  formatMultiValue,
  parseMultiValue,
  type InputField,
  type InputForm,
  type InputOptionSource,
  type InputSelectOption,
  type InputValues
} from "./inputForm";
import type { ListLinearOptionsResult } from "../bridge/cerebralBridge";
import { eventLabel, pickableEvents, useSportsEvents } from "../sports/sportsEvents";
import { recipientLabel, useMessageRecipients } from "./messageRecipients";
import { useBridge } from "../state/BridgeProvider";
import { quickActionLabel } from "../shell/quickActionRegistry";
import { useActionStatus } from "../state/ActionStatusProvider";
import { useUiPosture } from "../state/useUiPosture";
import { useInputs } from "../state/InputProvider";
import { useAppearance } from "../state/AppearanceProvider";
import { useTypewriter } from "../shell/useTypewriter";

/**
 * The Input region (docs/quick-actions/PLAN.md): the centre panel's lower right — below the
 * consciousness stream, above the quick-action grid.
 *
 * Unlike the Report region this one is a **bordered panel**: it is interactive and needs a hit
 * target, where a report is something you read. A Picker will render here too, with a filter
 * field and a result list above the same footer.
 */
export function InputRegion({
  contentRef,
  ready = true
}: {
  /** Attached to the body so `CenterShade` can measure the surface it has to hug. */
  contentRef?: RefObject<HTMLDivElement | null>;
  /**
   * False while the centre is still handing over — the ambient greeting is on its way out and this
   * surface must not land on top of it. `CenterStage` owns that sequence; held after the hooks so
   * the form's options keep loading during the wait.
   */
  ready?: boolean;
} = {}) {
  const { openInputId, closeInput } = useInputs();
  // Same handover as the report: the outgoing form recedes before the next one arrives, rather
  // than being unmounted out from under itself.
  const { shown: openInputIdShown, leaving } = useLeaveTransition(openInputId);
  const { form, loading } = useInputForm(openInputIdShown ?? "");
  const picker = usePicker(openInputIdShown ?? "");
  const { reducedMotion } = useAppearance();
  const titleRef = useRef<HTMLHeadingElement>(null);

  const title = openInputIdShown
    ? (picker?.title ?? form?.title ?? quickActionLabel(openInputIdShown))
    : null;

  /**
   * Only the title writes itself in — deliberately not the whole surface.
   *
   * A report is prose you read, so typing all of it is the point. A form is a thing you act on:
   * watching its field labels and its Save button assemble character by character would make it
   * look broken and briefly unreadable, and would delay the first field you were reaching for.
   * The title is the one piece of prose here, so it carries the entrance and the rest arrives ready
   * to use. Safe to key on the title text, unlike a report's body — a form's title is fixed
   * copy, with none of the relative times that make report text drift on its own.
   */
  useTypewriter(titleRef, ready && title && !leaving ? `${openInputIdShown}:${title}` : null, {
    enabled: !reducedMotion
  });

  if (!openInputIdShown || !ready) {
    return null;
  }

  // A Picker and an Input share this region, so the label says which one it is — "search form"
  // for a list you pick from would misdescribe it to anyone who cannot see it.
  const surface = picker ? "picker" : "form";

  return (
    <section
      className="input-region"
      aria-label={`${quickActionLabel(openInputIdShown)} ${surface}`}
      data-leaving={leaving || undefined}
    >
      <header className="input-region__head">
        <h2 className="input-region__title" ref={titleRef}>
          {title}
        </h2>
        <button
          type="button"
          className="input-region__close"
          aria-label={`Close the ${quickActionLabel(openInputIdShown)} ${surface}`}
          onClick={closeInput}
        >
          ×
        </button>
      </header>

      <div className="input-region__scroll">
        <div className="input-region__content" ref={contentRef}>
          {picker ? (
            <PickerBody key={picker.actionId} picker={picker} onDone={closeInput} />
          ) : loading ? (
            <p className="input-region__pending">Loading…</p>
          ) : form ? (
            // Keyed so switching between two Inputs starts from a clean set of values rather than
            // carrying the previous form's typing across.
            <InputFormBody key={form.actionId} form={form} onDone={closeInput} />
          ) : (
            <p className="input-region__pending">This action isn’t built yet.</p>
          )}
        </div>
      </div>
    </section>
  );
}

/**
 * A Picker: a filter field, the results, and one action per row (docs/quick-actions/PLAN.md).
 *
 * **A row is the submit.** There is no Go button, because there is nothing to collect — choosing
 * is the whole interaction. The footer keeps only Cancel, so the region's grammar stays the one
 * the forms established.
 *
 * Searches are **debounced and last-write-wins**: a slower earlier query must never overwrite the
 * results of a later one, or the list would settle on answers to a question the user has already
 * moved past.
 */
function PickerBody({ picker, onDone }: { picker: Picker; onDone: () => void }) {
  const { announce } = useActionStatus();
  const { readOnly } = useUiPosture();
  // The stage stack. `take-notes` is two pickers (course, then note) and this is the whole
  // mechanism for that: a stage IS a picker, so Back is generic and no picker implements it.
  const [stages, setStages] = useState<readonly Picker[]>([picker]);
  const active = stages[stages.length - 1];
  const [query, setQuery] = useState("");
  const [outcome, setOutcome] = useState<PickerOutcome | null>(null);
  const [searching, setSearching] = useState(true);
  const [choosing, setChoosing] = useState<string | null>(null);
  // Monotonic, so a stale response can be recognized and dropped rather than rendered.
  const latest = useRef(0);
  const filter = useRef<HTMLInputElement | null>(null);

  // Focus moves into the filter when the picker opens, and again on every stage change — arriving
  // at a list of notes with the cursor somewhere else would make the second stage feel like a
  // different surface. Done here rather than with `autoFocus` because that prop is the page-load
  // kind this codebase lints against; this is the other kind, following a press the user made.
  useEffect(() => {
    filter.current?.focus();
  }, [active]);

  useEffect(() => {
    const token = ++latest.current;
    setSearching(true);
    const timer = window.setTimeout(() => {
      void active
        .search(query)
        .then((next) => {
          if (latest.current === token) {
            setOutcome(next);
          }
        })
        .catch(() => {
          if (latest.current === token) {
            // An empty list with no explanation would read as "you have no notes", which is a
            // claim this does not get to make when the read itself failed.
            setOutcome({ results: [], notice: { message: "That search couldn’t be run." } });
          }
        })
        .finally(() => {
          if (latest.current === token) {
            setSearching(false);
          }
        });
    }, PICKER_DEBOUNCE_MS);
    return () => window.clearTimeout(timer);
  }, [active, query]);

  function choose(result: PickerResult) {
    setChoosing(result.id);
    void active
      // The query rides along because some rows are about what was TYPED rather than about a
      // result — `+ New note “Lecture 3”` names the note it is about to create.
      .choose(result, query)
      .then((choice) => {
        if (isPickerStage(choice)) {
          // A new stage starts from an empty filter: carrying "stat" into a list of that course's
          // notes would silently hide most of them.
          setStages((current) => [...current, choice.next]);
          setQuery("");
          setOutcome(null);
          return;
        }
        announce(choice.message, choice.failed ? "error" : undefined);
        if (!choice.failed) {
          onDone();
        }
      })
      .catch(() => {
        announce(`${active.title} failed — the bridge did not accept it.`, "error");
      })
      .finally(() => setChoosing(null));
  }

  function back() {
    setStages((current) => (current.length > 1 ? current.slice(0, -1) : current));
    setQuery("");
    setOutcome(null);
  }

  const results = outcome?.results ?? [];

  /**
   * Enter chooses the first row — the Spotlight/Obsidian gesture, and the one people expect after
   * typing a filter. It is deliberately the *first row* rather than a separate "best match": the
   * list is already ordered, so what Enter does is exactly what the eye is on.
   */
  function onFilterKeyDown(event: React.KeyboardEvent<HTMLInputElement>) {
    if (event.key === "Escape" && stages.length > 1) {
      // Escape steps back a stage before it closes the whole picker.
      event.preventDefault();
      back();
      return;
    }
    if (event.key !== "Enter" || results.length === 0 || choosing !== null || readOnly) {
      return;
    }
    event.preventDefault();
    choose(results[0]);
  }

  return (
    <div className="input-region__picker">
      {/* Which stage you are in. Only past the first: the region header already names the action,
          and repeating "Take notes" above "Take notes" says nothing. */}
      {stages.length > 1 ? <p className="picker__stage">{active.title}</p> : null}

      <input
        ref={filter}
        className="input-field__control"
        type="search"
        autoComplete="off"
        value={query}
        disabled={readOnly}
        placeholder={active.placeholder}
        aria-label={`${active.title} filter`}
        aria-controls="picker-results"
        onChange={(event) => setQuery(event.target.value)}
        onKeyDown={onFilterKeyDown}
      />

      <ul className="picker__results" id="picker-results">
        {results.map((result) => (
          <li key={result.id}>
            <button
              type="button"
              className="picker__result"
              disabled={readOnly || choosing !== null}
              onClick={() => choose(result)}
            >
              <span className="picker__result-label">{result.label}</span>
              {result.detail ? (
                <span className="picker__result-detail">{result.detail}</span>
              ) : null}
              {result.meta ? <span className="picker__result-meta">{result.meta}</span> : null}
            </button>
          </li>
        ))}
      </ul>

      {/* Searching and empty are different states and never share a message: one is "wait", the
          other is "there is nothing", and rendering the second while the first is true is a lie
          that resolves itself half a second later. */}
      {results.length === 0 ? (
        <p className="input-region__pending">{searching ? "Searching…" : active.emptyLabel}</p>
      ) : null}

      {outcome?.notice ? (
        <PickerNoticeView notice={outcome.notice} onAnnounce={announce} disabled={readOnly} />
      ) : null}

      <footer className="input-region__footer">
        {stages.length > 1 ? (
          <button type="button" className="input-region__cancel" onClick={back}>
            Back
          </button>
        ) : null}
        <button type="button" className="input-region__cancel" onClick={onDone}>
          Cancel
        </button>
      </footer>
    </div>
  );
}

/** A picker's statement about what it cannot see, with the one step that would fix it. */
function PickerNoticeView({
  notice,
  onAnnounce,
  disabled
}: {
  notice: PickerNotice;
  onAnnounce: (message: string, severity?: "error") => void;
  disabled: boolean;
}) {
  const [running, setRunning] = useState(false);

  function run() {
    if (!notice.action) {
      return;
    }
    setRunning(true);
    void notice.action
      .run()
      .then((outcome) => onAnnounce(outcome.message, outcome.failed ? "error" : undefined))
      .catch(() => onAnnounce("That didn’t work.", "error"))
      .finally(() => setRunning(false));
  }

  return (
    <p className="picker__notice">
      {notice.message}
      {notice.action ? (
        <button
          type="button"
          className="input-field__picker-button"
          disabled={disabled || running}
          onClick={run}
        >
          {running ? "Working…" : notice.action.label}
        </button>
      ) : null}
    </p>
  );
}

function InputFormBody({ form, onDone }: { form: InputForm; onDone: () => void }) {
  const { announce } = useActionStatus();
  const { readOnly } = useUiPosture();
  const [values, setValues] = useState<InputValues>(() => initialValues(form));
  const [submitting, setSubmitting] = useState(false);

  const fields = renderableFields(form);
  // Fetched once per form open rather than once per field: three Linear dropdowns would otherwise
  // make three identical requests. Not cached across opens either — a key pasted in Settings a
  // moment ago must take effect on the next open, not on the next launch.
  const linear = useLinearWorkspace(fields.some(usesLinearProvider));
  // The second remote option source, fetched the same way and for the same reason. A third would
  // be the point to generalize this into one provider-registry hook rather than a third one-off.
  const sports = useSportsEvents(fields.some((field) => providerOf(field) === "sportsEvents"));
  // The third remote option source, and the point at which the one-offs were collapsed: they now
  // share one shape (`RemoteOptions`) so a fourth is a table entry rather than another hook.
  const recipients = useMessageRecipients(
    fields.some((field) => providerOf(field) === "messageRecipients")
  );
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
          linear={linear}
          sports={sports}
          recipients={recipients}
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

/** The provider id behind a field's options, or "" for a static list. */
function providerOf(field: InputField): string {
  return field.source?.kind === "provider" ? field.source.provider : "";
}

/** Whether a field's options come from the Linear workspace. */
function usesLinearProvider(field: InputField): boolean {
  return providerOf(field).startsWith("linear");
}

/** Re-exported for the field view's props; the hook itself lives with the sports read. */
type SportsEventsState = ReturnType<typeof useSportsEvents>;

/** The Linear workspace, or an honest reason it could not be read. */
interface LinearState {
  readonly result: ListLinearOptionsResult | null;
  readonly failed: boolean;
}

/**
 * Reads the Linear workspace when a form needs it, and only then.
 *
 * One request serves every Linear dropdown in the form, because they are three views of the same
 * document — the teams, and the projects and labels scoped inside each.
 */
function useLinearWorkspace(enabled: boolean): LinearState {
  const bridge = useBridge();
  const [state, setState] = useState<LinearState>({ result: null, failed: false });

  useEffect(() => {
    if (!enabled) {
      return;
    }
    let cancelled = false;
    void bridge
      .listLinearOptions()
      .then((result) => {
        if (!cancelled) {
          setState({ result, failed: false });
        }
      })
      .catch(() => {
        if (!cancelled) {
          setState({ result: null, failed: true });
        }
      });
    return () => {
      cancelled = true;
    };
  }, [bridge, enabled]);

  return state;
}

/**
 * The options a Linear provider offers, given the workspace and the scoping team.
 *
 * Projects and labels are read out of the **selected team**, never flattened across the workspace:
 * a project belongs to one team, and offering one from another would produce a write Linear
 * rejects. With no team chosen yet there is nothing to scope by, so the list is empty rather than
 * a guess.
 */
export function linearOptions(
  provider: string,
  workspace: ListLinearOptionsResult | null,
  teamId: string
): readonly InputSelectOption[] {
  if (!workspace) {
    return [];
  }
  if (provider === "linearTeams") {
    return workspace.teams.map((team) => ({ value: team.id, label: team.name }));
  }
  const team = workspace.teams.find((candidate) => candidate.id === teamId);
  if (!team) {
    return [];
  }
  const source = provider === "linearProjects" ? team.projects : team.labels;
  return source.map((option) => ({ value: option.id, label: option.name }));
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
  linear,
  sports,
  recipients,
  disabled,
  onChange
}: {
  field: InputField;
  values: InputValues;
  linear: LinearState;
  sports: SportsEventsState;
  recipients: ReturnType<typeof useMessageRecipients>;
  disabled: boolean;
  onChange: (name: string, next: string) => void;
}) {
  const id = `input-field-${field.name}`;
  const calendars = useOptionSource(field.source);
  const isLinear = usesLinearProvider(field);
  const isSports = providerOf(field) === "sportsEvents";
  const isRecipients = providerOf(field) === "messageRecipients";
  // A scoped field reads the value of the field it depends on, so a project list narrows to the
  // chosen team instead of spanning the workspace.
  const scopeValue = field.scopedBy ? (values[field.scopedBy] ?? "") : "";
  const provider = field.source?.kind === "provider" ? field.source.provider : "";
  const options = isRecipients
    ? (recipients.result?.recipients ?? []).map((recipient) => ({
        value: `${recipient.kind}:${recipient.id}`,
        label: recipientLabel(recipient)
      }))
    : isSports
    ? pickableEvents(sports.result?.events ?? []).map((event) => ({
        value: event.id,
        label: eventLabel(event)
      }))
    : isLinear
      ? linearOptions(provider, linear.result, scopeValue)
      : calendars.options;
  const unavailable = isRecipients
    ? recipients.failed || recipients.result?.available === false || recipients.result?.reason != null
    : isSports
    ? sports.failed || sports.result?.available === false || sports.result?.reason != null
    : isLinear
      ? linear.failed || linear.result?.available === false || linear.result?.reason != null
      : calendars.unavailable;
  const hint = unavailable
    ? isRecipients
      ? (recipients.result?.reason ??
        "Contacts couldn\u2019t be read. Grant Contacts access in System Settings.")
      : isSports
      ? sports.result?.reason ?? "Scores couldn\u2019t be read right now."
        : isLinear
          ? "Your Linear workspace couldn\u2019t be read. Check the API key under Settings \u2192 Setup."
          : "Your calendars couldn\u2019t be read — this will use the default."
    : isSports && sports.loading
      ? "Loading today\u2019s games…"
      : field.hint;
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

  // A required select with exactly one real option has no decision to make, so it makes it: the
  // field stays visible and overridable, but nobody has to click through a dropdown of one. This
  // is not the same as inferring a value — with two options it stays blank and asks.
  const onlyOption = field.required && value === "" && options.length === 1 ? options[0] : null;
  useEffect(() => {
    if (onlyOption) {
      onChange(field.name, onlyOption.value);
      onChange(`${field.name}Label`, onlyOption.label);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [onlyOption?.value]);

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
      ) : field.kind === "combobox" ? (
        <ComboboxControl
          id={id}
          field={field}
          options={options}
          value={value}
          disabled={disabled}
          describedBy={describedBy}
          onChange={onChange}
        />
      ) : field.kind === "multiSelect" ? (
        <MultiSelectControl
          id={id}
          field={field}
          options={options}
          value={value}
          disabled={disabled}
          describedBy={describedBy}
          onChange={onChange}
        />
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

/**
 * A `multiSelect`: one checkbox per option, not a native `<select multiple>`.
 *
 * A native multi-select needs cmd-click to add a second value and gives no hint that it can hold
 * more than one — for a list of labels someone picks two of, that is a control that hides its own
 * capability. Checkboxes say what they do.
 *
 * The chosen ids are packed into this field's single slot, and their **labels** into the companion
 * `<name>Label` slot, so a confirmation can name them in words the way every other select does.
 */
function MultiSelectControl({
  id,
  field,
  options,
  value,
  disabled,
  describedBy,
  onChange
}: {
  id: string;
  field: InputField;
  options: readonly InputSelectOption[];
  value: string;
  disabled: boolean;
  describedBy?: string;
  onChange: (name: string, next: string) => void;
}) {
  const chosen = parseMultiValue(value);
  const atCap = field.maxSelected !== undefined && chosen.length >= field.maxSelected;

  function toggle(optionValue: string, checked: boolean) {
    // Rebuilt from the option order rather than by appending, so the packed value reads in the
    // same order as the list however it was clicked.
    const next = options
      .map((option) => option.value)
      .filter((candidate) =>
        candidate === optionValue ? checked : chosen.includes(candidate)
      );
    onChange(field.name, formatMultiValue(next));
    onChange(
      `${field.name}Label`,
      formatMultiValue(
        next.map((id) => options.find((option) => option.value === id)?.label ?? id)
      )
    );
  }

  if (options.length === 0) {
    return (
      <p className="input-field__empty" id={id}>
        Nothing to choose from.
      </p>
    );
  }

  return (
    // `aria-label` rather than the sibling `<label for>`: a `for` attribute associates with a form
    // control, and a checkbox group is not one — without this the group would be unnamed.
    <div
      className="input-field__multi"
      id={id}
      role="group"
      aria-label={field.label}
      aria-describedby={describedBy}
    >
      {options.map((option) => (
        <label className="input-field__check" key={option.value}>
          <input
            type="checkbox"
            checked={chosen.includes(option.value)}
            // At the cap only the already-chosen boxes stay live, so unchecking is always possible.
            disabled={disabled || (atCap && !chosen.includes(option.value))}
            onChange={(event) => toggle(option.value, event.target.checked)}
          />
          <span>{option.label}</span>
        </label>
      ))}
    </div>
  );
}

/**
 * A `combobox`: typeahead over a list too long to scan.
 *
 * Deliberately not used for a short list — a dropdown of ten labels beats a search box over ten
 * labels. It exists because an address book is the case where scanning stops working.
 *
 * **Nothing is chosen until something is chosen.** Typing filters; it never sets the value. The
 * stored value only changes when a result is picked, so a half-typed name can never become a
 * recipient — which for this particular form is the difference between a message and a mistake.
 */
function ComboboxControl({
  id,
  field,
  options,
  value,
  disabled,
  describedBy,
  onChange
}: {
  id: string;
  field: InputField;
  options: readonly InputSelectOption[];
  value: string;
  disabled: boolean;
  describedBy?: string;
  onChange: (name: string, next: string) => void;
}) {
  const [query, setQuery] = useState("");
  const chosen = options.find((option) => option.value === value);
  const needle = query.trim().toLowerCase();
  const matches =
    needle.length === 0
      ? []
      : options.filter((option) => option.label.toLowerCase().includes(needle)).slice(0, 8);

  function choose(option: InputSelectOption) {
    onChange(field.name, option.value);
    // The label rides along so the confirmation can name the recipient in words.
    onChange(`${field.name}Label`, option.label);
    setQuery("");
  }

  if (chosen) {
    return (
      <div className="input-field__chosen">
        <span className="input-field__chosen-label">{chosen.label}</span>
        <button
          type="button"
          className="input-field__picker-button"
          disabled={disabled}
          onClick={() => {
            onChange(field.name, "");
            onChange(`${field.name}Label`, "");
          }}
        >
          Change
        </button>
      </div>
    );
  }

  return (
    <div className="input-field__combobox">
      <input
        id={id}
        className="input-field__control"
        type="text"
        role="combobox"
        aria-expanded={matches.length > 0}
        aria-controls={`${id}-matches`}
        autoComplete="off"
        value={query}
        disabled={disabled}
        placeholder={field.placeholder}
        aria-describedby={describedBy}
        onChange={(event) => setQuery(event.target.value)}
      />
      {matches.length > 0 ? (
        <ul className="input-field__matches" id={`${id}-matches`} role="listbox">
          {matches.map((option) => (
            <li key={option.value}>
              <button
                type="button"
                className="input-field__match"
                role="option"
                aria-selected={false}
                onClick={() => choose(option)}
              >
                {option.label}
              </button>
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}
