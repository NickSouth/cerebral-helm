import { useDashboardState } from "../state/DashboardStateProvider";
import { useActiveMode } from "../shell/useActiveMode";
import { composeDailyBrief, type DailyBriefSnapshot } from "./dailyBrief";
import { composeOpenSchedule, type OpenScheduleSnapshot } from "./openSchedule";
import { composeSuggestAMovie, type SuggestAMovieSnapshot } from "./suggestAMovie";
import type { DashboardState } from "../state/dashboardState";
import type { ReportDocument } from "./reportDocument";

/**
 * The **assembler** stage: reads the live providers already streaming into dashboard state and
 * builds each report's typed snapshot, then hands it to that report's composer.
 *
 * Nothing new crosses the bridge for any of the three reports — weather, the calendar, and the
 * Canvas / TMDB widget feeds are already live in the dashboard, so v1 composes entirely from
 * state it holds. When a model becomes the composer it will consume the same snapshot types.
 */
export function useReportDocument(reportId: string, now: Date = new Date()): ReportDocument | null {
  const state = useDashboardState();
  const calendarProfile = useActiveMode().calendarProfile;

  switch (reportId) {
    case "daily-brief":
      return composeDailyBrief(dailyBriefSnapshot(state, calendarProfile, now));
    case "open-schedule":
      return composeOpenSchedule(openScheduleSnapshot(state, calendarProfile));
    case "suggest-a-movie":
      return composeSuggestAMovie(suggestAMovieSnapshot(state, now));
    default:
      // Registered as a Report but not composed yet — the region renders its honest not-yet
      // state rather than an empty document, which would look like a successful, empty report.
      return null;
  }
}

/** Live wins over the per-mode bootstrap channel, as the Today panel resolves it (NIC-126). */
function scheduleOf(state: DashboardState, calendarProfile?: string) {
  const schedule =
    (calendarProfile ? state.liveSchedule?.[calendarProfile] : undefined) ?? state.regions.schedule;
  return {
    state: schedule.state,
    // A stale or unavailable channel's leftover items are not today's schedule.
    items: schedule.state === "ready" || schedule.state === "stale" ? schedule.items : []
  };
}

/**
 * A widget's payload — the live-streamed value when a producer has delivered one, else whichever
 * rail slot currently holds that widget.
 *
 * A report can name a widget the active mode does not render (School's courses feed while
 * Entertainment is active), so a slot miss is `unavailable` rather than an error: the report says
 * so honestly instead of claiming an empty feed.
 */
function widget(state: DashboardState, widgetId: string) {
  const slot = [state.regions.widgets.left, state.regions.widgets.right].find(
    (candidate) => candidate.widgetId === widgetId
  );
  // No live payload and no slot holding it: report `unavailable` rather than inventing a
  // placeholder widget, so the composer says so honestly instead of showing an empty feed.
  const data = state.liveWidgets?.[widgetId] ?? slot;
  if (!data) {
    return { state: "unavailable", items: [] } as const;
  }

  const items = (data.data as { items?: readonly unknown[] } | undefined)?.items;
  return {
    state: data.state,
    items: data.state === "ready" || data.state === "stale" ? (items ?? []) : []
  } as const;
}

function dailyBriefSnapshot(
  state: DashboardState,
  calendarProfile: string | undefined,
  now: Date
): DailyBriefSnapshot {
  const weather = state.liveWeather ?? state.weather ?? null;
  return {
    now,
    weather: weather
      ? { state: weather.state, temperatureF: weather.temperatureF, condition: weather.condition }
      : null,
    schedule: scheduleOf(state, calendarProfile),
    // No mail provider exists yet (PRD excludes Workspace from the MVP), so the count is absent
    // rather than zero — a fabricated "0 unread" would be a claim we cannot make.
    unreadCount: null
  };
}

function openScheduleSnapshot(
  state: DashboardState,
  calendarProfile: string | undefined
): OpenScheduleSnapshot {
  const courses = widget(state, "courses");
  const deadlines = widget(state, "deadlines");

  return {
    // The Canvas courses feed carries the code the resolver joins on; a row without an id falls
    // back to its name so the grouping key is still stable.
    courses: (courses.items as ReadonlyArray<{ id?: string; name?: string; code?: string }>)
      .filter((item) => typeof item.name === "string")
      .map((item) => ({ id: item.id ?? (item.name as string), name: item.name as string, code: item.code })),
    coursesState: courses.state,
    schedule: scheduleOf(state, calendarProfile),
    deadlines: (
      deadlines.items as ReadonlyArray<{
        id?: string;
        title?: string;
        dueAt?: string;
        courseName?: string;
      }>
    )
      .filter((item) => typeof item.title === "string")
      .map((item, index) => ({
        id: item.id ?? `deadline-${index}`,
        title: item.title as string,
        dueAt: item.dueAt,
        courseName: item.courseName
      })),
    deadlinesState: deadlines.state
  };
}

function suggestAMovieSnapshot(state: DashboardState, now: Date): SuggestAMovieSnapshot {
  const releases = widget(state, "releases");
  return {
    now,
    releases: (
      releases.items as ReadonlyArray<{
        id?: string;
        title?: string;
        mediaType?: string;
        year?: number;
      }>
    )
      .filter((item) => typeof item.title === "string")
      .map((item, index) => ({
        id: item.id ?? `release-${index}`,
        title: item.title as string,
        mediaType: item.mediaType === "tv" ? "tv" : "movie",
        year: item.year
      })),
    releasesState: releases.state
  };
}
