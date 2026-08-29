import { useDashboardState } from "../state/DashboardStateProvider";
import { useActiveMode } from "../shell/useActiveMode";
import { composeDailyBrief, type DailyBriefSnapshot } from "./dailyBrief";
import { composeOpenSchedule, type OpenScheduleSnapshot } from "./openSchedule";
import { composeSuggestAMovie, type SuggestAMovieSnapshot } from "./suggestAMovie";
import { composeCheckScoreboard } from "./checkScoreboard";
import { composeSystemChecks } from "./systemChecks";
import { composeEmailReport } from "./emailReport";
import { unreadFacts } from "./unreadCount";
import { useUnreadMail } from "./useUnreadMail";
import { useReportComposition } from "./useReportComposition";
import { useSystemChecksRun } from "./useSystemChecksRun";
import { useSportsEvents } from "../sports/sportsEvents";
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
export function useReportDocument(
  reportId: string,
  now: Date | undefined = undefined,
  params: readonly string[] = []
): { document: ReportDocument | null; refresh: () => void; revision?: string } {
  const at = now ?? new Date();
  const state = useDashboardState();
  const calendarProfile = useActiveMode().calendarProfile;
  // Called unconditionally — a hook inside the switch would change the hook order between reports.
  // The read is a no-op unless this is the report that needs it, and it comes through the shared
  // cache, so opening the report normally reuses the fetch the picker just made.
  const sports = useSportsEvents(reportId === "check-scoreboard");
  // Same shape, same reason: called unconditionally so hook order never depends on which report is
  // open. It starts a run when this report opens and re-runs on demand; the RESULTS arrive as
  // events and land in dashboard state, so the composer below reads them like any other feed.
  const checks = useSystemChecksRun(reportId === "system-status-checks");
  // Same discipline: called unconditionally so hook order never depends on which report is open,
  // and it reads nothing unless this is the report that needs it.
  const mail = useUnreadMail(reportId === "email-report");
  // Same discipline again: called unconditionally so hook order never depends on which report is
  // open, and it composes nothing unless this is the report that needs it. ONE composition per
  // open, not per render — this function runs on every render, from a fresh `new Date()`.
  const composition = useReportComposition("daily-brief", reportId === "daily-brief");
  // The email report is model-composed too (NIC-259): it reads message bodies host-side and writes
  // a per-thread summary. Same once-per-open hook; the deterministic list below is now its fallback.
  const emailComposition = useReportComposition("email-report", reportId === "email-report");

  // The refresh is the sports read's, because that is the only report composed from a fetch. A
  // report built from ambient dashboard state has nothing to re-request, and says so by not
  // declaring itself refreshable.
  const refresh = sports.refresh;

  switch (reportId) {
    case "check-scoreboard":
      return { refresh, document: composeCheckScoreboard({
        events: sports.result?.events ?? [],
        selected: params,
        loading: sports.loading,
        reason: sports.failed
          ? "Scores couldn\u2019t be read right now."
          : sports.result?.available === false
            ? "Scores need the macOS host."
            : (sports.result?.reason ?? null)
      }) };
    case "daily-brief":
      return {
        refresh: composition.refresh,
        // The reveal is keyed on WHICH COMPOSITION this is — the generation alone, and
        // deliberately NOT its status or its block count. Both of those move when the body lands
        // partway through a read, and re-keying there blanks the header the reader is already
        // looking at and types it again. Verified in the browser: including `status` here produced
        // exactly that rewrite. What legitimately means "write this again" is a NEW composition,
        // which is what the generation counts.
        revision: `${composition.generation}`,
        document: composeDailyBrief(dailyBriefSnapshot(state, calendarProfile, at), composition)
      };
    case "open-schedule":
      return { refresh, document: composeOpenSchedule(openScheduleSnapshot(state, calendarProfile)) };
    case "system-status-checks":
      // The one report that re-runs rather than re-reads: `refresh` is the run itself.
      return {
        refresh: checks.rerun,
        // The live metrics come from the same region the bottom bar reads, so the header is
        // current by construction rather than by a second subscription.
        document: composeSystemChecks(state.systemChecks, state.regions.systemHealth)
      };
    case "email-report":
      return {
        // Refresh re-composes, which re-assembles the mail host-side — the model path is the fetch,
        // exactly as it is for the daily brief.
        refresh: emailComposition.refresh,
        revision: `${emailComposition.generation}`,
        document: composeEmailReport(
          {
            mail: mail.result,
            // The count comes from the live channel, not from the capped list: counting rows would
            // report "5 unread" for an inbox holding fifty.
            unread: unreadFacts(state.mail),
            loading: mail.loading
          },
          emailComposition
        )
      };
    case "suggest-a-movie":
      return { refresh, document: composeSuggestAMovie(suggestAMovieSnapshot(state, at)) };
    default:
      // Registered as a Report but not composed yet — the region renders its honest not-yet
      // state rather than an empty document, which would look like a successful, empty report.
      return { refresh, document: null };
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
      ? {
          state: weather.state,
          temperatureF: weather.temperatureF,
          condition: weather.condition,
          highF: weather.highF
        }
      : null,
    schedule: scheduleOf(state, calendarProfile),
    // The live Gmail channel (2026-08-04). Absent unless it was actually measured: a count is
    // only rendered when `state === "ready"`, so "not connected" can never become a reassuring 0.
    unreadCount: unreadFacts(state.mail)
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
