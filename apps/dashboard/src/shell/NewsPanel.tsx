import { Panel } from "./Panel";
import { PanelGlyph } from "./PanelGlyph";
import { StaleMarker } from "../components/StaleMarker";
import { Unavailable } from "../components/Unavailable";
import { EmptyState } from "../components/EmptyState";
import { useDashboardState } from "../state/DashboardStateProvider";

/** L4 News (design spec §5.3): exactly the active mode's relevant headlines, degraded-aware. */
export function NewsPanel() {
  const { news } = useDashboardState().regions;
  const live = news.state === "ready" || news.state === "stale";
  const hasHeadlines = live && news.headlines.length > 0;

  return (
    <Panel label="News" labelId="region-news" icon={<PanelGlyph name="news" />}>
      {hasHeadlines ? (
        <>
          {news.state === "stale" ? <StaleMarker /> : null}
          <ul className="news">
            {news.headlines.map((headline) => (
              <li key={headline.id} className="news__item">
                <span className="news__title">{headline.title}</span>
                <span className="news__source">{headline.source}</span>
              </li>
            ))}
          </ul>
        </>
      ) : news.state === "unavailable" ? (
        <Unavailable label={news.emptyMessage ?? "News is unavailable"} />
      ) : (
        // ready/empty/stale with no headlines: a healthy zero-result, not a disabled capability.
        <EmptyState label={news.emptyMessage ?? "No headlines right now"} />
      )}
    </Panel>
  );
}
