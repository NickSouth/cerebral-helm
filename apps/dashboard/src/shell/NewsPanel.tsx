import { Panel } from "./Panel";
import { PanelGlyph } from "./PanelGlyph";
import { StaleMarker } from "../components/StaleMarker";
import { Unavailable } from "../components/Unavailable";
import { EmptyState } from "../components/EmptyState";
import { useDashboardState } from "../state/DashboardStateProvider";
import { useActiveMode } from "./useActiveMode";
import { useBridge } from "../state/BridgeProvider";
import { useActionStatus } from "../state/ActionStatusProvider";
import { useUiPosture } from "../state/useUiPosture";
import { submitWebOpen } from "./webOpen";
import type { NewsHeadline } from "../bridge/types";

/** L4 News (design spec §5.4): exactly the active mode's relevant headlines, degraded-aware. A
 *  headline with a `url` is a navigable link that opens the article in the browser through the
 *  `web.open` tool; one without a link renders as non-interactive text (never a dead button).
 *  Read-only recovery disables the links, and a rejected dispatch is surfaced honestly. */
export function NewsPanel() {
  const { regions, liveNews } = useDashboardState();
  const profile = useActiveMode().newsProfile;
  const bridge = useBridge();
  const { announce } = useActionStatus();
  const { readOnly } = useUiPosture();
  // Live per-profile headlines (NIC-127) win over the bootstrap region; the map is keyed by the
  // active mode's newsProfile and survives mode switches by construction (it lives outside
  // `regions`). Falls through to the mode-scoped bootstrap `news` until a producer streams.
  const news = (profile ? liveNews?.[profile] : undefined) ?? regions.news;
  const live = news.state === "ready" || news.state === "stale";
  const hasHeadlines = live && news.headlines.length > 0;

  const open = (headline: NewsHeadline) => {
    if (!headline.url) return;
    void submitWebOpen(bridge, headline.url)
      .then((receipt) => {
        if (!receipt.accepted) {
          announce(`I couldn't open that story — the command wasn't accepted.`, "error");
        }
      })
      .catch(() => {
        announce(`Opening that story failed — the bridge did not accept it.`, "error");
      });
  };

  return (
    <Panel label="News" labelId="region-news" icon={<PanelGlyph name="news" />}>
      {hasHeadlines ? (
        <>
          {news.state === "stale" ? <StaleMarker /> : null}
          <ul className="news">
            {news.headlines.map((headline) => (
              <li key={headline.id} className="news__item">
                {headline.url ? (
                  <button
                    type="button"
                    className="news__link"
                    disabled={readOnly}
                    aria-disabled={readOnly || undefined}
                    title={
                      readOnly
                        ? "Opening a story is paused while the dashboard is read-only"
                        : `Open "${headline.title}" in the browser`
                    }
                    onClick={() => {
                      open(headline);
                    }}
                  >
                    <span className="news__title">{headline.title}</span>
                    <span className="news__source">{headline.source}</span>
                  </button>
                ) : (
                  <>
                    <span className="news__title">{headline.title}</span>
                    <span className="news__source">{headline.source}</span>
                  </>
                )}
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
