import { parseMultiValue, type InputForm, type InputValues } from "./inputForm";

/**
 * `check-scoreboard` — a picker, not a write (quick actions phase 4).
 *
 * It is the first Input whose submit **opens a Report** rather than acting on the world. The two
 * regions already coexist and a report link can already open an input, so this is the symmetric
 * direction: the form collects which games, and the report renders them.
 *
 * Nothing crosses the command bus. Choosing games and reading scores is not an action, so routing
 * it through the executor would put a command in the log every time you looked at a scoreboard.
 */

/** The most events one report shows. Three fits the panel and is what was asked for. */
export const MAX_EVENTS = 3;

export function checkScoreboardForm(
  openReport: (reportId: string, params?: readonly string[]) => void
): InputForm {
  return {
    actionId: "check-scoreboard",
    title: "Check scoreboard",
    submitLabel: "Show",
    fields: [
      {
        name: "eventIds",
        label: "Games",
        kind: "multiSelect",
        required: true,
        maxSelected: MAX_EVENTS,
        source: { kind: "provider", provider: "sportsEvents" },
        hint: `Up to ${MAX_EVENTS}. Live games come first, then scheduled, then finished.`
      }
    ],
    async submit(values: InputValues) {
      const chosen = parseMultiValue(values.eventIds).slice(0, MAX_EVENTS);
      openReport("check-scoreboard", chosen);
      // The report is the result, so the status line says only what happened — the scores are on
      // screen a moment later and restating them here would be a second, staler copy.
      return { message: chosen.length === 1 ? "Showing 1 game." : `Showing ${chosen.length} games.` };
    }
  };
}
