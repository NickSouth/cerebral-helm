import { useMemo } from "react";
import { useBridge } from "../state/BridgeProvider";
import { useDashboardState } from "../state/DashboardStateProvider";
import { quickActionEntry } from "../shell/quickActionRegistry";
import { searchNotesPicker } from "./searchNotes";
import { takeNotesPicker, type CanvasCourse } from "./takeNotes";
import type { Picker } from "./picker";
import type { DashboardState } from "../state/dashboardState";

/**
 * Builds the Picker for an action, or `null` when the action is not one.
 *
 * The same shape as {@link useInputForm} and the report composers: the surface is shared, the
 * content is not. It checks the **registry's archetype** rather than keeping a second list of
 * which ids are pickers — the registry already knows what every action is, and a parallel list
 * could disagree with it.
 *
 * Memoized per action so the picker object is stable across renders: `PickerBody` searches in an
 * effect keyed on it, and a fresh object each render would re-search on every keystroke's
 * re-render rather than on the query actually changing.
 */
export function usePicker(actionId: string): Picker | null {
  const bridge = useBridge();
  const state = useDashboardState();
  const canvasCourses = canvasCoursesOf(state);
  // Keyed on the course NAMES rather than the array identity: the widget feed re-publishes on its
  // own cadence, and a new array of the same courses must not rebuild the picker mid-search.
  const courseKey = canvasCourses.map((course) => `${course.code ?? ""}|${course.name}`).join("\n");

  return useMemo(() => {
    if (quickActionEntry(actionId)?.archetype !== "picker") {
      return null;
    }
    switch (actionId) {
      case "search-notes":
        return searchNotesPicker(bridge);
      case "take-notes":
        return takeNotesPicker(bridge, canvasCourses);
      default:
        return null;
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [actionId, bridge, courseKey]);
}

/**
 * The Canvas courses the School widgets already stream (NIC-132), read the same way the schedule
 * report reads them.
 *
 * Deliberately **not** a new bridge read: the enrolled-course list is already in dashboard state,
 * and a second source for it could disagree with the widget the user is looking at. An absent or
 * unready feed is an empty list — the picker then shows what is in the vault, which is the honest
 * answer when Canvas has told us nothing.
 */
function canvasCoursesOf(state: DashboardState): readonly CanvasCourse[] {
  const slot = [state.regions.widgets.left, state.regions.widgets.right].find(
    (candidate) => candidate.widgetId === "courses"
  );
  const data = state.liveWidgets?.courses ?? slot;
  if (!data || (data.state !== "ready" && data.state !== "stale")) {
    return [];
  }
  const items = (data.data as { items?: readonly unknown[] } | undefined)?.items ?? [];
  return (items as ReadonlyArray<{ name?: unknown; code?: unknown }>)
    .filter((item): item is { name: string; code?: string } => typeof item.name === "string")
    .map((item) => ({ name: item.name, code: typeof item.code === "string" ? item.code : undefined }));
}
