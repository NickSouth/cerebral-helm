import {
  createEventForm,
  defaultCalendarId,
  defaultRange,
  nextHalfHour,
  toWallClock,
  withModeTag
} from "./createEvent";
import { initialValues, missingRequired } from "./inputForm";
import type { CerebralBridge, CreateCalendarEventInput } from "../bridge/cerebralBridge";

/** `create-event` — the Input archetype's stress test (docs/quick-actions/PLAN.md phase 3). */

function bridgeSpy(
  result: { eventId: string; calendarTitle?: string; awaitingConfirmation: boolean } = {
    eventId: "evt_1",
    calendarTitle: "Work",
    awaitingConfirmation: false
  }
) {
  const sent: CreateCalendarEventInput[] = [];
  const bridge = {
    createCalendarEvent(input: CreateCalendarEventInput) {
      sent.push(input);
      return Promise.resolve(result);
    }
  } as unknown as CerebralBridge;
  return { bridge, sent };
}

describe("create-event defaults", () => {
  it("rounds the start up to the next half hour and runs an hour", () => {
    expect(toWallClock(nextHalfHour(new Date("2026-08-03T14:07:00")))).toBe("2026-08-03T14:30");
    expect(toWallClock(nextHalfHour(new Date("2026-08-03T14:31:00")))).toBe("2026-08-03T15:00");
    // Exactly on a boundary stays there rather than skipping a half hour.
    expect(toWallClock(nextHalfHour(new Date("2026-08-03T14:30:00")))).toBe("2026-08-03T14:30");

    expect(defaultRange(new Date("2026-08-03T14:07:00"))).toEqual({
      start: "2026-08-03T14:30",
      end: "2026-08-03T15:30"
    });
  });

  it("emits LOCAL wall-clock strings, not UTC instants", () => {
    // The time a user typed is the time they meant. A UTC conversion here would silently shift
    // every event by the machine's offset.
    const wall = toWallClock(new Date(2026, 7, 3, 9, 5));
    expect(wall).toBe("2026-08-03T09:05");
    expect(wall).not.toContain("Z");
  });

  it("preselects the calendar the user mapped to the active mode", () => {
    // The mode-aware default: one registration, four modes, correct default in each.
    const map = { "cal-work": "executive", "cal-school": "school" };
    expect(defaultCalendarId(map, "executive")).toBe("cal-work");
    expect(defaultCalendarId(map, "school")).toBe("cal-school");
  });

  it("preselects nothing when the mode maps to no calendar", () => {
    // Falling back to "Default calendar" is honest; guessing at one of the user's calendars
    // would put an event somewhere they never chose.
    expect(defaultCalendarId({ "cal-work": "executive" }, "entertainment")).toBe("");
    expect(defaultCalendarId(undefined, "executive")).toBe("");
    expect(defaultCalendarId({}, "executive")).toBe("");
  });
});

/**
 * The mode tag is the layer that decides which mode's schedule shows the event
 * (`CalendarRelevanceResolver`): the `#[mode]` tag beats the calendar→mode mapping, which beats the
 * default mode. Without it an event created in a mode with no mapped calendar fell to Executive and
 * disappeared from the mode it was made in.
 */
describe("create-event mode tag", () => {
  it("appends the raw mode id on its own line, which the catalog resolves directly", () => {
    expect(withModeTag("Bring the deck.", "school")).toBe("Bring the deck.\n\n#school");
  });

  it("writes the tag alone when the user left the notes empty", () => {
    expect(withModeTag("", "developer")).toBe("#developer");
    expect(withModeTag("   \n ", "developer")).toBe("#developer");
  });

  it("never doubles a tag the user typed themselves", () => {
    expect(withModeTag("#school study group", "school")).toBe("#school study group");
    expect(withModeTag("Notes\n\n#School", "school")).toBe("Notes\n\n#School");
  });

  it("treats a longer tag as a different tag", () => {
    // `#schoolwork` is not `#school`: a prefix match would skip the tag that actually files it.
    expect(withModeTag("#schoolwork", "school")).toBe("#schoolwork\n\n#school");
  });
});

describe("create-event form", () => {
  const now = new Date("2026-08-03T14:07:00");
  const MODES = [
    { id: "executive", label: "Executive" },
    { id: "school", label: "School" }
  ];

  function form(modeId = "executive") {
    const { bridge, sent } = bridgeSpy();
    return {
      sent,
      form: createEventForm({
        bridge,
        now,
        modeId,
        modes: MODES,
        calendarModeMap: { "cal-work": "executive" }
      })
    };
  }

  it("seeds a title-less form with a ready-to-use range and the mode's calendar", () => {
    const values = initialValues(form().form);
    expect(values.title).toBe("");
    expect(values.startsAt).toBe("2026-08-03T14:30");
    expect(values.endsAt).toBe("2026-08-03T15:30");
    expect(values.calendarId).toBe("cal-work");
    // The mode the user is standing in, pre-chosen and overridable.
    expect(values.mode).toBe("executive");
  });

  it("defaults the Mode field to the active mode in every mode", () => {
    expect(initialValues(form("school").form).mode).toBe("school");
  });

  it("blocks submission on the title alone — the range is already filled in", () => {
    const built = form().form;
    expect(missingRequired(built, initialValues(built)).map((field) => field.label)).toEqual([
      "Event"
    ]);
  });

  it("sends the typed values, omitting blank optionals rather than sending empty strings", () => {
    const { form: built, sent } = form();
    void built.submit({
      title: "  Board prep  ",
      startsAt: "2026-08-03T16:00",
      endsAt: "2026-08-03T17:00",
      calendarId: "cal-work",
      calendarIdLabel: "Work",
      mode: "executive",
      location: "   ",
      notes: ""
    });

    expect(sent).toEqual([
      {
        title: "Board prep",
        startsAt: "2026-08-03T16:00",
        endsAt: "2026-08-03T17:00",
        calendarId: "cal-work",
        // The chosen calendar's LABEL rides along so a confirmation can name it in words.
        calendarTitle: "Work",
        location: undefined,
        // Blank notes still carry the tag — it is what files the event under the chosen mode.
        notes: "#executive"
      }
    ]);
  });

  it("files the event under the CHOSEN mode, not the one the form was opened in", () => {
    // The whole point of the field being overridable: a School event created from Executive.
    const { form: built, sent } = form("executive");
    void built.submit({
      title: "Stats final",
      startsAt: "2026-08-03T16:00",
      endsAt: "2026-08-03T17:00",
      mode: "school",
      notes: "Room 2"
    });
    expect(sent[0].notes).toBe("Room 2\n\n#school");
  });

  it("falls back to the active mode if the Mode field somehow arrives blank", () => {
    const { form: built, sent } = form("school");
    void built.submit({
      title: "Anything",
      startsAt: "2026-08-03T16:00",
      endsAt: "2026-08-03T17:00",
      mode: ""
    });
    expect(sent[0].notes).toBe("#school");
  });

  it("omits the calendar entirely when the user leaves it on Default", () => {
    const { form: built, sent } = form();
    void built.submit({
      title: "Anything",
      startsAt: "2026-08-03T16:00",
      endsAt: "2026-08-03T17:00",
      calendarId: "",
      calendarIdLabel: ""
    });
    expect(sent[0].calendarId).toBeUndefined();
  });

  it("says where the event landed AND which mode will show it", async () => {
    // The tag is invisible in the schedule, so this line is the only place the user sees it.
    const outcome = await form().form.submit({
      title: "Board prep",
      startsAt: "2026-08-03T16:00",
      endsAt: "2026-08-03T17:00",
      mode: "school"
    });
    expect(outcome.message).toBe("Created “Board prep” in Work, under School.");
  });

  it("never claims 'created' while a confirmation is still pending", async () => {
    // The gated case: an agent-proposed call, or any call while "ask before all actions" is on.
    const { bridge } = bridgeSpy({ eventId: "cmd_1", awaitingConfirmation: true });
    const built = createEventForm({ bridge, now, modeId: "executive", modes: MODES });
    const outcome = await built.submit({
      title: "Board prep",
      startsAt: "2026-08-03T16:00",
      endsAt: "2026-08-03T17:00"
    });
    expect(outcome.message).toMatch(/needs your confirmation/);
    expect(outcome.message).not.toMatch(/Created/);
  });
});
