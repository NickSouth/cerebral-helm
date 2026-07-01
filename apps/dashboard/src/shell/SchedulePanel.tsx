import { Panel } from "./Panel";
import { PanelGlyph } from "./PanelGlyph";
import { StaleMarker } from "../components/StaleMarker";
import { Unavailable } from "../components/Unavailable";
import { EmptyState } from "../components/EmptyState";
import { useDashboardState } from "../state/DashboardStateProvider";
import { formatClock } from "./format";

/** The calendar reserves a fixed four-row event area so the widget height never changes. */
const EVENT_SLOTS = 4;

/** Big current time (digital feel). Masked in visual snapshots (see shell.spec.ts) for determinism. */
function formatNowTime(now: Date): string {
  return now.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
}

/** Full current date under the clock. */
function formatNowDate(now: Date): string {
  return now.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" });
}

/**
 * L1 Today / Tonight (design spec §5.1): the live clock and date, up to four upcoming events
 * (color dot · title · right-aligned start), and a "View full schedule" control. The event area
 * always reserves four rows so the widget keeps a constant height regardless of event count.
 */
export function SchedulePanel({ now = new Date() }: { now?: Date } = {}) {
  const { schedule } = useDashboardState().regions;
  const live = schedule.state === "ready" || schedule.state === "stale";
  const events = live ? schedule.items.slice(0, EVENT_SLOTS) : [];

  return (
    <Panel label="Today" labelId="region-today" icon={<PanelGlyph name="today" />}>
      <div className="calendar">
        <p className="calendar__time">{formatNowTime(now)}</p>
        <p className="calendar__date">{formatNowDate(now)}</p>

        {schedule.state === "stale" ? <StaleMarker /> : null}

        {schedule.state === "unavailable" ? (
          <div className="calendar__events calendar__events--degraded">
            <Unavailable label={schedule.emptyMessage ?? "Schedule is unavailable"} />
          </div>
        ) : live && events.length === 0 ? (
          <div className="calendar__events calendar__events--degraded">
            <EmptyState label={schedule.emptyMessage ?? "Nothing scheduled"} />
          </div>
        ) : (
          <ul className="calendar__events">
            {Array.from({ length: EVENT_SLOTS }, (_, index) => {
              const event = events[index];
              if (!event) {
                return <li key={`empty-${index}`} className="calendar__event calendar__event--empty" aria-hidden="true" />;
              }
              return (
                <li key={event.id} className="calendar__event">
                  <span className="calendar__dot" data-kind={event.kind} aria-hidden="true" />
                  <span className="calendar__event-title">{event.title}</span>
                  <span className="calendar__event-time">{formatClock(event.start)}</span>
                </li>
              );
            })}
          </ul>
        )}

        <button
          type="button"
          className="calendar__view"
          disabled
          aria-disabled="true"
          title="The full calendar opens on the macOS host"
        >
          View full schedule<span aria-hidden="true"> →</span>
        </button>
      </div>
    </Panel>
  );
}
