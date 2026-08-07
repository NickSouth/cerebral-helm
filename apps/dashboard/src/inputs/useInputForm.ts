import { useEffect, useState } from "react";
import { useBridge } from "../state/BridgeProvider";
import { useDashboardState } from "../state/DashboardStateProvider";
import { toModeId } from "../tokens/tokens";
import { createEventForm } from "./createEvent";
import { gitCloneForm } from "./gitClone";
import { createTicketForm } from "./createTicket";
import { createPlaylistForm } from "./createPlaylist";
import { createProjectForm } from "./createProject";
import { checkScoreboardForm } from "./checkScoreboard";
import { sendTextForm } from "./sendText";
import { useReports } from "../state/ReportProvider";
import { submitYouTubeSearch } from "../shell/youtubeSearch";
import type { CerebralBridge } from "../bridge/cerebralBridge";
import type { InputForm, InputValues } from "./inputForm";

/**
 * Builds the form for an Input action. One function per action, selected by id — the same shape as
 * the report composers, and for the same reason: the surface is shared, the content is not.
 *
 * `loading` exists because a form's **initial values** may depend on a persisted read, and a
 * default that arrives after the user starts typing is worse than a moment's wait: it would either
 * be ignored or clobber what they wrote. The region shows a settling state instead.
 */
export function useInputForm(actionId: string): { form: InputForm | null; loading: boolean } {
  const bridge = useBridge();
  const { mode, modes } = useDashboardState();
  const { openReport } = useReports();
  const calendarModeMap = useCalendarModeMap(actionId === "create-event");

  switch (actionId) {
    case "capture-note":
      return { form: captureNoteForm(bridge), loading: false };
    case "search-youtube":
      return { form: searchYouTubeForm(bridge), loading: false };
    case "git-clone":
      return { form: gitCloneForm(bridge), loading: false };
    case "create-ticket":
      return { form: createTicketForm(bridge), loading: false };
    case "create-playlist":
      return { form: createPlaylistForm(bridge), loading: false };
    case "create-project":
      return { form: createProjectForm(bridge), loading: false };
    case "check-scoreboard":
      return { form: checkScoreboardForm(openReport), loading: false };
    case "send-text":
      return { form: sendTextForm(bridge), loading: false };
    case "create-event":
      return calendarModeMap.loading
        ? { form: null, loading: true }
        : {
            form: createEventForm({
              bridge,
              now: new Date(),
              modeId: toModeId(mode),
              // The Mode field's options are the resolved modes from bootstrap, not a hardcoded
              // four: config decides which modes exist, and the tag it writes is the raw mode id.
              modes: modes.map(({ id, label }) => ({ id, label })),
              calendarModeMap: calendarModeMap.map
            }),
            loading: false
          };
    default:
      // Registered as an Input but not built yet — the region says so rather than rendering an
      // empty form, which would look like an action that asks for nothing.
      return { form: null, loading: false };
  }
}

/**
 * The user's calendar→mode mapping (NIC-126), read once when a form that needs it opens.
 *
 * A failed read yields an empty map rather than blocking: the form then offers the default
 * calendar, which writes wherever the system would — an honest fallback, not a guess at which of
 * the user's calendars they meant.
 */
function useCalendarModeMap(enabled: boolean): {
  map?: Readonly<Record<string, string>>;
  loading: boolean;
} {
  const bridge = useBridge();
  const [map, setMap] = useState<Readonly<Record<string, string>> | undefined>(undefined);

  useEffect(() => {
    if (!enabled) {
      return;
    }
    let cancelled = false;
    void bridge
      .getSettings()
      .then((snapshot) => {
        if (!cancelled) {
          setMap(snapshot.calendarModeMap ?? {});
        }
      })
      // A failed read resolves to an empty map rather than staying pending forever — the form
      // then offers the default calendar instead of hanging on "Loading…".
      .catch(() => {
        if (!cancelled) {
          setMap({});
        }
      });
    return () => {
      cancelled = true;
    };
  }, [bridge, enabled]);

  // Derived, not stored: `loading` must be true from the very FIRST render in which this is
  // enabled, before any effect has run. A flag seeded in `useState` is computed while the form is
  // still closed, so it would read `false` on the render that builds the form — and the default
  // would arrive after the body had already seeded its values, silently losing it.
  return { map, loading: enabled && map === undefined };
}

/**
 * `search-youtube` — one field, one bus command, no new surface (quick actions phase 4, action 1).
 *
 * It reports only that the search was **dispatched**, never that a page opened: the receipt says
 * whether the command was accepted, and nothing more. The tool is macOS-only, so in the browser the
 * command is accepted and then fails downstream as unavailable-in-phase — claiming "Opened YouTube"
 * off the host would be a fabricated success.
 */
function searchYouTubeForm(bridge: CerebralBridge): InputForm {
  return {
    actionId: "search-youtube",
    title: "Search YouTube",
    submitLabel: "Search",
    fields: [
      {
        name: "query",
        label: "Search",
        kind: "text",
        required: true,
        placeholder: "What are you looking for?"
      }
    ],
    async submit(values: InputValues) {
      const query = values.query.trim();
      const receipt = await submitYouTubeSearch(bridge, query);
      if (!receipt.accepted) {
        return { message: `I couldn't search for “${query}” — the command wasn't accepted.`, failed: true };
      }
      return { message: `Searching YouTube for “${query}”.` };
    }
  };
}

/**
 * `capture-note` — the simplest possible Input: a title, a body, and a real write.
 *
 * It replaced the old fixed-content handler, which captured a note titled "Quick note" with an
 * empty body because no content-entry affordance existed. That handler is gone rather than kept
 * alongside: two ways to capture a note, one of which cannot carry content, is a worse surface
 * than one.
 */
function captureNoteForm(bridge: CerebralBridge): InputForm {
  return {
    actionId: "capture-note",
    title: "Capture note",
    submitLabel: "Capture",
    fields: [
      { name: "title", label: "Title", kind: "text", required: true, placeholder: "What is it?" },
      { name: "body", label: "Note", kind: "textarea", placeholder: "Anything worth keeping." }
    ],
    async submit(values: InputValues) {
      const result = await bridge.captureNote({
        title: values.title.trim(),
        body: values.body ?? "",
        kind: "quick-capture"
      });
      // Reports what the bridge actually returned, never a fabricated success.
      return { message: `Captured “${values.title.trim()}” (${result.noteId}).` };
    }
  };
}
