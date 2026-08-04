import {
  createEventForm,
  defaultCalendarId,
  defaultRange,
  nextHalfHour,
  toWallClock
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

describe("create-event form", () => {
  const now = new Date("2026-08-03T14:07:00");

  function form(modeId = "executive") {
    const { bridge, sent } = bridgeSpy();
    return {
      sent,
      form: createEventForm({
        bridge,
        now,
        modeId,
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
        notes: undefined
      }
    ]);
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

  it("says where the event landed", async () => {
    const outcome = await form().form.submit({
      title: "Board prep",
      startsAt: "2026-08-03T16:00",
      endsAt: "2026-08-03T17:00"
    });
    expect(outcome.message).toBe("Created “Board prep” in Work.");
  });

  it("never claims 'created' while a confirmation is still pending", async () => {
    // The gated case: an agent-proposed call, or any call while "ask before all actions" is on.
    const { bridge } = bridgeSpy({ eventId: "cmd_1", awaitingConfirmation: true });
    const built = createEventForm({ bridge, now, modeId: "executive" });
    const outcome = await built.submit({
      title: "Board prep",
      startsAt: "2026-08-03T16:00",
      endsAt: "2026-08-03T17:00"
    });
    expect(outcome.message).toMatch(/needs your confirmation/);
    expect(outcome.message).not.toMatch(/Created/);
  });
});
