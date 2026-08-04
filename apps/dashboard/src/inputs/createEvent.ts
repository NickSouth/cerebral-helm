import type { CerebralBridge } from "../bridge/cerebralBridge";
import type { InputForm, InputValues } from "./inputForm";

/**
 * `create-event` — the Input archetype's stress test: multi-field, an external write, a
 * provider-backed dropdown, and one registration serving four modes.
 *
 * **Mode-aware default, not a per-slot parameter.** The slot appears in all four modes and should
 * default to that mode's calendar. The category *is* the active mode, so the form reads the
 * calendar→mode mapping the user already configured in Settings (NIC-126) and preselects the
 * calendar mapped to the mode they are in. One id, one registration, correct default everywhere —
 * and no per-slot parameter mechanism, which nothing yet requires.
 *
 * **The form writes the mode tag, because the calendar mapping alone cannot carry it.**
 * `CalendarRelevanceResolver` resolves an event to a mode in three layers: a `#[mode]` tag in the
 * notes, else the event's calendar→mode mapping, else the default mode (Executive, whose profile is
 * the catch-all). Writing through layer 2 only meant an event created in a mode with no mapped
 * calendar fell to Executive and **vanished from the mode it was made in** — and even with a mapping
 * configured, changing the Calendar dropdown silently moved the event to another mode's schedule.
 *
 * So the Mode field is explicit and overridable (create a School event from Executive), and its tag
 * is written into the notes on submit. The tag is the layer that *wins*, so the choice is honest
 * whatever calendar the event lands in — and unlike a local sidecar it travels with the event,
 * surviving an edit made later in Calendar.app or on a phone. The tag token is the **raw mode id**,
 * which `CalendarProfileCatalog.mode(forTag:)` resolves directly, so no alias table has to be
 * mirrored into the web layer.
 */

/** Rounds up to the next half hour — a sensible start for an event created "now". */
export function nextHalfHour(now: Date): Date {
  const rounded = new Date(now);
  rounded.setSeconds(0, 0);
  rounded.setMinutes(rounded.getMinutes() + (30 - (rounded.getMinutes() % 30 || 30)));
  return rounded;
}

/** `2026-08-03T14:00` — the local wall-clock form `datetime-local` uses and the contract expects. */
export function toWallClock(date: Date): string {
  const pad = (value: number) => String(value).padStart(2, "0");
  return (
    `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}` +
    `T${pad(date.getHours())}:${pad(date.getMinutes())}`
  );
}

export function defaultRange(now: Date): { start: string; end: string } {
  const start = nextHalfHour(now);
  const end = new Date(start);
  end.setHours(end.getHours() + 1);
  return { start: toWallClock(start), end: toWallClock(end) };
}

/**
 * The calendar this mode should default to, from the user's own calendar→mode mapping.
 * Returns `""` when the mode maps to nothing — the form then offers "Default calendar", which
 * writes wherever the system would, rather than guessing at one of the user's calendars.
 */
export function defaultCalendarId(
  calendarModeMap: Readonly<Record<string, string>> | undefined,
  modeId: string
): string {
  if (!calendarModeMap) {
    return "";
  }
  const match = Object.entries(calendarModeMap).find(([, mapped]) => mapped === modeId);
  return match ? match[0] : "";
}

/**
 * The notes to write, with the chosen mode's `#[mode]` tag appended.
 *
 * On its own line at the end, so it never runs into a sentence the user typed, and never added
 * twice — a tag they wrote themselves is left exactly where they put it. An empty note becomes the
 * tag alone rather than a blank line followed by one.
 */
export function withModeTag(notes: string, modeId: string): string {
  const trimmed = notes.trim();
  const tag = `#${modeId}`;
  // Word-boundary match so `#school` is not considered already present because `#schoolwork` is.
  const alreadyTagged = new RegExp(`(^|\\s)#${modeId}(?![\\w-])`, "i").test(trimmed);
  if (alreadyTagged) {
    return trimmed;
  }
  return trimmed.length > 0 ? `${trimmed}\n\n${tag}` : tag;
}

/** A mode the event can be filed under — the four resolved modes from bootstrap state. */
export interface CreateEventMode {
  readonly id: string;
  readonly label: string;
}

export function createEventForm(options: {
  readonly bridge: CerebralBridge;
  readonly now: Date;
  readonly modeId: string;
  readonly modes: readonly CreateEventMode[];
  readonly calendarModeMap?: Readonly<Record<string, string>>;
}): InputForm {
  const { bridge, now, modeId, modes, calendarModeMap } = options;
  const range = defaultRange(now);

  return {
    actionId: "create-event",
    title: "Create event",
    submitLabel: "Create",
    fields: [
      { name: "title", label: "Event", kind: "text", required: true, placeholder: "What is it?" },
      {
        name: "startsAt",
        endName: "endsAt",
        label: "When",
        kind: "datetimeRange",
        required: true,
        initialValue: range.start,
        initialEndValue: range.end
      },
      {
        name: "mode",
        label: "Mode",
        kind: "select",
        source: { kind: "static", options: modes.map(({ id, label }) => ({ value: id, label })) },
        initialValue: modeId,
        hint: "Which mode's schedule shows this event."
      },
      {
        name: "calendarId",
        label: "Calendar",
        kind: "select",
        source: { kind: "provider", provider: "calendars" },
        emptyOptionLabel: "Default calendar",
        initialValue: defaultCalendarId(calendarModeMap, modeId),
        // Seeded from the *active* mode, not from the Mode field above: the two are independent by
        // design. Mode decides which schedule shows the event (the tag outranks the calendar
        // mapping either way); Calendar decides where it is stored.
        hint: "Where the event is stored. Defaults to the calendar you mapped to this mode."
      },
      { name: "location", label: "Location", kind: "text", placeholder: "Optional" },
      { name: "notes", label: "Notes", kind: "textarea", placeholder: "Optional" }
    ],
    async submit(values: InputValues) {
      const result = await bridge.createCalendarEvent({
        title: values.title.trim(),
        startsAt: values.startsAt,
        endsAt: values.endsAt,
        calendarId: values.calendarId || undefined,
        // Carried so a confirmation prompt can name the calendar in words; an id alone would be
        // unreadable there.
        calendarTitle: values.calendarIdLabel || undefined,
        location: values.location?.trim() || undefined,
        // Always sent: the tag alone is worth writing even when the user left the notes empty,
        // because it is what files the event under the mode they chose.
        notes: withModeTag(values.notes ?? "", values.mode || modeId)
      });

      // Never report "created" for something still waiting on the user's approval.
      if (result.awaitingConfirmation) {
        return { message: `“${values.title.trim()}” needs your confirmation before it's created.` };
      }
      const where = result.calendarTitle ? ` in ${result.calendarTitle}` : "";
      // Names the mode as well as the calendar: the tag is invisible in the schedule, so the
      // confirmation line is the only place the user sees which mode will show the event.
      const filed = modes.find((candidate) => candidate.id === values.mode)?.label;
      const under = filed ? `, under ${filed}` : "";
      return { message: `Created “${values.title.trim()}”${where}${under}.` };
    }
  };
}
