import { Panel } from "./Panel";
import { PanelGlyph } from "./PanelGlyph";
import { Unavailable } from "../components/Unavailable";
import { useDashboardState } from "../state/DashboardStateProvider";

/** L4 News (design spec §5.3): exactly the active mode's relevant headlines, degraded-aware. */
export function NewsPanel() {
  const { news } = useDashboardState().regions;
  const live = news.state === "ready" || news.state === "stale";

  return (
    <Panel label="News" labelId="region-news" icon={<PanelGlyph name="news" />}>
      {live && news.headlines.length > 0 ? (
        <ul className="news">
          {news.headlines.map((headline) => (
            <li key={headline.id} className="news__item">
              <span className="news__title">{headline.title}</span>
              <span className="news__source">{headline.source}</span>
            </li>
          ))}
        </ul>
      ) : (
        <Unavailable label={news.emptyMessage ?? "No headlines"} />
      )}
    </Panel>
  );
}
