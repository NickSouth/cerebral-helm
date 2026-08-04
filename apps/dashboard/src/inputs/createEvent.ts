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

export function createEventForm(options: {
  readonly bridge: CerebralBridge;
  readonly now: Date;
  readonly modeId: string;
  readonly calendarModeMap?: Readonly<Record<string, string>>;
}): InputForm {
  const { bridge, now, modeId, calendarModeMap } = options;
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
        name: "calendarId",
        label: "Calendar",
        kind: "select",
        source: { kind: "provider", provider: "calendars" },
        initialValue: defaultCalendarId(calendarModeMap, modeId),
        hint: "Defaults to the calendar you mapped to this mode."
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
        notes: values.notes?.trim() || undefined
      });

      // Never report "created" for something still waiting on the user's approval.
      if (result.awaitingConfirmation) {
        return { message: `“${values.title.trim()}” needs your confirmation before it's created.` };
      }
      const where = result.calendarTitle ? ` in ${result.calendarTitle}` : "";
      return { message: `Created “${values.title.trim()}”${where}.` };
    }
  };
}
