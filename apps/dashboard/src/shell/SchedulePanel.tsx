import { Panel } from "./Panel";
import { PanelGlyph } from "./PanelGlyph";
import { Unavailable } from "../components/Unavailable";
import { useDashboardState } from "../state/DashboardStateProvider";
import { formatClock } from "./format";

/** L1 Today/Tonight (design spec §5.3): the active mode's schedule, degraded-aware. */
export function SchedulePanel() {
  const { schedule } = useDashboardState().regions;
  const live = schedule.state === "ready" || schedule.state === "stale";

  return (
    <Panel label="Today" labelId="region-today" icon={<PanelGlyph name="today" />}>
      {live && schedule.items.length > 0 ? (
        <ul className="schedule">
          {schedule.items.map((item) => (
            <li key={item.id} className="schedule__item">
              <span className="schedule__time" data-kind={item.kind}>
                {formatClock(item.start)}
              </span>
              <span className="schedule__title">{item.title}</span>
            </li>
          ))}
        </ul>
      ) : (
        <Unavailable label={schedule.emptyMessage ?? "Nothing scheduled."} />
      )}
    </Panel>
  );
}
