import { useEffect, useRef, useState } from "react";
import { Panel } from "./Panel";
import { AppGlyph } from "./AppGlyph";
import { MoreAppsPicker } from "./MoreAppsPicker";
import { toModeId } from "../tokens/tokens";
import type { AppReference, ChromeProfile, DiscoveredApp, UrlReference } from "../bridge/cerebralBridge";
import { useActiveMode } from "./useActiveMode";
import { appDefinition } from "../appCatalog/appCatalog";
import { useBridge } from "../state/BridgeProvider";
import { useActionStatus } from "../state/ActionStatusProvider";
import { useDashboardState } from "../state/DashboardStateProvider";
import { useUiPosture } from "../state/useUiPosture";

/** The five app slots + a sixth "More Apps" control (design spec §5.6: one-to-five apps + More). */
const APP_SLOTS = 5;

/** A pin silhouette shown in empty app slots — an addable placeholder (pinning is a Mac capability). */
function PinGlyph() {
  return (
    <svg
      className="app-glyph"
      viewBox="0 0 24 24"
      width="22"
      height="22"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <path d="M9 3.5h6l-1 5 3 3v1.5H7V11.5l3-3-1-5z" />
      <path d="M12 14v6.5" />
    </svg>
  );
}

/** A 3×3 grid of tiles — the app-drawer glyph for the "More Apps" menu. */
function AppsGridGlyph() {
  const coords = [4, 9.75, 15.5];
  return (
    <svg
      className="app-glyph"
      viewBox="0 0 24 24"
      width="22"
      height="22"
      fill="currentColor"
      aria-hidden="true"
      focusable="false"
    >
      {coords.flatMap((y) =>
        coords.map((x) => <rect key={`${x}-${y}`} x={x} y={y} width="4.5" height="4.5" rx="1.2" />)
      )}
    </svg>
  );
}

/**
 * C1 Quick Apps (design spec §5.6): the active mode's configured app shortcuts, padded to five
 * fixed slots (empty slots show a "Pin app" placeholder), plus a final "More Apps" control — six
 * boxes spanning the panel edge-to-edge. Each slot mirrors the mode toggle: icon over label.
 * Apps render with placeholder category glyphs (real OS icons on Mac).
 *
 * Launch tiles are live exactly when the runtime reports `native.app.open` available
 * (FR-SHL-06): a tile dispatches the deterministic `open <id>` command through the bridge —
 * the same envelope as the palette (FR-CMD-01) — and surfaces a rejected reference honestly.
 * Pinning and app discovery remain Mac capabilities that land with their adapters, so those
 * controls stay honest-disabled.
 */
export function QuickApps() {
  const { quickApps } = useActiveMode();
  const bridge = useBridge();
  const { announce } = useActionStatus();
  const { readOnly } = useUiPosture();
  const state = useDashboardState();
  const apps = quickApps.slice(0, APP_SLOTS);
  const emptySlots = Math.max(0, APP_SLOTS - apps.length);

  const appOpen = state.capabilities?.["native.app.open"];
  const canLaunch = appOpen?.available === true && !readOnly;
  const disabledReason = readOnly
    ? "Unavailable while the app is in read-only recovery"
    : (appOpen?.degradedReason ?? "Launching apps is available on the macOS host");

  // More Apps rides the read-only discovery capability (NIC-119) — honest-disabled
  // until the runtime reports it, like every native-gated control.
  const appsList = state.capabilities?.["native.apps.list"];
  const canDiscover = appsList?.available === true && !readOnly;
  const discoverDisabledReason = readOnly
    ? "Unavailable while the app is in read-only recovery"
    : (appsList?.degradedReason ?? "App discovery is available on the macOS host");
  const [pickerOpen, setPickerOpen] = useState(false);

  // Real OS icons on tiles (NIC-119): once discovery is available, map each
  // configured reference id onto its discovered app (icon + real name). The
  // category glyph stays the honest fallback for anything unmatched.
  const [discovered, setDiscovered] = useState<ReadonlyMap<string, DiscoveredApp>>(new Map());
  useEffect(() => {
    if (!canDiscover) {
      return;
    }
    let cancelled = false;
    void bridge
      .listApps()
      .then((result) => {
        if (cancelled) {
          return;
        }
        const byReference = new Map<string, DiscoveredApp>();
        for (const app of result.apps) {
          if (app.referenceId) {
            byReference.set(app.referenceId, app);
          }
        }
        setDiscovered(byReference);
      })
      .catch(() => {
        // Discovery failing never degrades the tiles — glyphs remain.
      });
    return () => {
      cancelled = true;
    };
  }, [canDiscover, bridge]);

  // Pinned URL references (NIC-146) resolve their label + favicon from the URL
  // catalog — the counterpart of the app-discovery join above, since a URL has no
  // app-catalog entry. Re-fetched when the pinned set changes so a just-added URL
  // renders with its real label rather than its slug id, and again whenever a
  // `mode.quickapps.changed` event fires — a landed favicon re-emits that event
  // with unchanged pins (NIC-147), so the tile upgrades globe → real icon live.
  const [urls, setUrls] = useState<ReadonlyMap<string, UrlReference>>(new Map());
  const pinnedKey = quickApps.join(",");
  useEffect(() => {
    if (quickApps.length === 0) {
      return;
    }
    let cancelled = false;
    const refresh = () => {
      void bridge
        .listUrls()
        .then((result) => {
          if (cancelled) {
            return;
          }
          setUrls(new Map(result.urls.map((url) => [url.id, url])));
        })
        .catch(() => {
          // Degrade: a URL tile falls back to its id label, never breaks the row.
        });
    };
    refresh();
    const unsubscribe = bridge.subscribe((event) => {
      if (event.type === "mode.quickapps.changed") {
        refresh();
      }
    });
    return () => {
      cancelled = true;
      unsubscribe();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [bridge, pinnedKey]);

  // Chrome profiles (NIC-151): the avatar map (directory → profile) badges any tile
  // that opens in a Chrome profile, and the reference map (id → app reference) lets a
  // pinned "Chrome — Work" tile resolve its label + profile. Re-fetched with the pins,
  // and on mode.quickapps.changed so a just-pinned profile tile renders at once.
  const [profilesByDir, setProfilesByDir] = useState<ReadonlyMap<string, ChromeProfile>>(new Map());
  const [chromeRefsById, setChromeRefsById] = useState<ReadonlyMap<string, AppReference>>(new Map());
  useEffect(() => {
    if (quickApps.length === 0) {
      return;
    }
    let cancelled = false;
    const refresh = () => {
      void bridge
        .listChromeProfiles()
        .then((result) => {
          if (cancelled) {
            return;
          }
          setProfilesByDir(new Map(result.profiles.map((p) => [p.directory, p])));
          setChromeRefsById(new Map(result.references.map((ref) => [ref.id, ref])));
        })
        .catch(() => {
          // Degrade: tiles fall back to no badge / id label, never break the row.
        });
    };
    refresh();
    const unsubscribe = bridge.subscribe((event) => {
      if (event.type === "mode.quickapps.changed") {
        refresh();
      }
    });
    return () => {
      cancelled = true;
      unsubscribe();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [bridge, pinnedKey]);

  // Left-click unpin path (owner decision): every pinned tile carries its own
  // unpin control — no trip through the picker. The write rides the same
  // validated override path; the mode.quickapps.changed event removes the tile.
  const unpin = (id: string) => {
    void bridge
      .updateQuickApps({
        modeId: toModeId(state.mode),
        quickApps: quickApps.filter((pinned) => pinned !== id)
      })
      .catch(() => {
        announce("Unpinning failed — the change could not be written.", "error");
      });
  };

  // Leading-edge debounce for tile clicks (NIC-151): a profiled URL's first click
  // launches Chrome and its window/tab takes a moment to appear, so rapid repeat
  // clicks in that gap would each open a duplicate tab before surfacing can engage.
  // The first click fires immediately; further clicks on the same tile within the
  // cooldown are ignored — making a launch effectively idempotent under fast clicks.
  const LAUNCH_COOLDOWN_MS = 800;
  const lastLaunchRef = useRef<Map<string, number>>(new Map());

  const launch = (id: string, label: string) => {
    const now = Date.now();
    if (now - (lastLaunchRef.current.get(id) ?? 0) < LAUNCH_COOLDOWN_MS) {
      return;
    }
    lastLaunchRef.current.set(id, now);
    void bridge
      .submitCommand({ rawInput: `open ${id}`, source: "dashboard" })
      .then((receipt) => {
        if (!receipt.accepted) {
          announce(`I couldn't open ${label} — it isn't a configured app reference.`, "error");
        }
      })
      .catch(() => {
        announce(`Opening ${label} failed — the bridge did not accept the command.`, "error");
      });
  };

  // The Chrome app icon (for pinned "Chrome — <profile>" tiles), if discovery found it.
  const chromeIcon = [...discovered.values()].find((a) => a.bundleId === "com.google.Chrome")?.iconPng;

  return (
    <Panel label="Quick Apps" labelId="region-quick-apps">
      <ul className="quick-apps">
        {apps.map((id) => {
          const urlRef = urls.get(id);
          const chromeRef = chromeRefsById.get(id);
          const app = appDefinition(id);
          const discoveredApp = discovered.get(id);
          const label = urlRef?.label ?? chromeRef?.label ?? app?.label ?? discoveredApp?.name ?? id;
          // The Chrome profile this tile opens in (a profiled URL, or a Chrome-profile
          // app tile) → its avatar badge, when the profile was discovered (NIC-151).
          const profileDir = urlRef?.profile ?? chromeRef?.profile;
          const profileAvatar = profileDir ? profilesByDir.get(profileDir)?.iconPng : undefined;
          return (
            <li key={id} className="quick-app-slot">
              {!readOnly ? (
                <button
                  type="button"
                  className="quick-app__unpin"
                  aria-label={`Unpin ${label}`}
                  title={`Unpin ${label}`}
                  onClick={() => unpin(id)}
                >
                  ×
                </button>
              ) : null}
              <button
                type="button"
                className="quick-app"
                disabled={!canLaunch}
                aria-disabled={!canLaunch}
                title={canLaunch ? `Open ${label}` : disabledReason}
                onClick={canLaunch ? () => launch(id, label) : undefined}
              >
                <span className="quick-app__icon">
                  {urlRef ? (
                    urlRef.iconPng ? (
                      // A pinned URL with a fetched favicon (NIC-147).
                      <img
                        className="quick-app__real-icon"
                        src={`data:image/png;base64,${urlRef.iconPng}`}
                        alt=""
                      />
                    ) : (
                      // No favicon yet: the globe placeholder (NIC-146/147).
                      <AppGlyph category="browser" />
                    )
                  ) : chromeRef ? (
                    // A pinned "Chrome — <profile>" tile (NIC-151): Chrome's icon.
                    chromeIcon ? (
                      <img className="quick-app__real-icon" src={`data:image/png;base64,${chromeIcon}`} alt="" />
                    ) : (
                      <AppGlyph category="browser" />
                    )
                  ) : discoveredApp?.iconPng ? (
                    <img
                      className="quick-app__real-icon"
                      src={`data:image/png;base64,${discoveredApp.iconPng}`}
                      alt=""
                    />
                  ) : (
                    <AppGlyph category={app?.category ?? "files"} />
                  )}
                  {/* The Chrome-profile avatar badge (NIC-151), bottom-left corner. */}
                  {profileAvatar ? (
                    <img
                      className="quick-app__profile-badge"
                      src={`data:image/png;base64,${profileAvatar}`}
                      alt=""
                      aria-hidden="true"
                    />
                  ) : null}
                </span>
                <span className="quick-app__label">{label}</span>
              </button>
            </li>
          );
        })}
        {Array.from({ length: emptySlots }, (_, index) => (
          <li key={`pin-${index}`}>
            <button
              type="button"
              className="quick-app quick-app--pin"
              disabled={!canDiscover}
              aria-disabled={!canDiscover}
              title={canDiscover ? "Pin an app to this slot" : discoverDisabledReason}
              onClick={canDiscover ? () => setPickerOpen(true) : undefined}
            >
              <span className="quick-app__icon" aria-hidden="true">
                <PinGlyph />
              </span>
              <span className="quick-app__label">Pin app</span>
            </button>
          </li>
        ))}
        <li>
          <button
            type="button"
            className="quick-app quick-app--more"
            disabled={!canDiscover}
            aria-disabled={!canDiscover}
            title={canDiscover ? "Browse installed applications" : discoverDisabledReason}
            onClick={canDiscover ? () => setPickerOpen(true) : undefined}
          >
            <span className="quick-app__icon" aria-hidden="true">
              <AppsGridGlyph />
            </span>
            <span className="quick-app__label">More Apps</span>
          </button>
        </li>
      </ul>
      {pickerOpen ? <MoreAppsPicker onClose={() => setPickerOpen(false)} /> : null}
    </Panel>
  );
}
