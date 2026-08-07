import { useEffect, useState } from "react";
import { useBridge } from "../state/BridgeProvider";
import { appDefinition, type AppCategory } from "../appCatalog/appCatalog";
import type {
  AppReference,
  ChromeProfile,
  DiscoveredApp,
  UrlReference
} from "../bridge/cerebralBridge";

/** How one reference resolves to an on-screen icon (NIC-142). Mirrors the join Quick
 *  Apps does per tile: a discovered app's OS icon, a pinned URL's favicon, or a
 *  Chrome-profile tile's Chrome icon + account-avatar badge, with an honest category
 *  glyph as the fallback while discovery loads or when nothing matches. */
export interface ResolvedIcon {
  readonly label: string;
  /** The real icon (app OS icon, Chrome icon, or URL favicon) when available. */
  readonly iconPng?: string;
  /** The category glyph to draw when `iconPng` is absent. */
  readonly fallbackCategory: AppCategory;
  /** The Chrome-profile account avatar, badged bottom-left when the tile opens in a profile. */
  readonly profileAvatarPng?: string;
}

/**
 * Resolve a set of reference ids to their icons the same way Quick Apps does
 * (NIC-119/146/147/151) — one shared join so the layout hotswap pill and the app
 * grid stay pixel-identical. Fetches app discovery, the URL catalog, and Chrome
 * profiles once for the given refs, and re-fetches on `mode.quickapps.changed`
 * (a landed favicon re-emits it with unchanged pins, so tiles upgrade globe → real
 * icon live). Every fetch degrades silently: an unresolved ref falls back to its
 * category glyph and its provided label, never breaking the row.
 *
 * Returns a `resolve(ref, fallbackLabel?)` reader rather than a map so callers pass
 * the session-provided label as the fallback for a ref not yet in any catalog.
 */
export function useResolvedAppIcons(
  refs: readonly string[]
): (ref: string, fallbackLabel?: string) => ResolvedIcon {
  const bridge = useBridge();
  const key = refs.join(",");
  const [discovered, setDiscovered] = useState<ReadonlyMap<string, DiscoveredApp>>(new Map());
  const [urls, setUrls] = useState<ReadonlyMap<string, UrlReference>>(new Map());
  const [profilesByDir, setProfilesByDir] = useState<ReadonlyMap<string, ChromeProfile>>(new Map());
  const [chromeRefsById, setChromeRefsById] = useState<ReadonlyMap<string, AppReference>>(new Map());

  useEffect(() => {
    if (refs.length === 0) {
      return;
    }
    let cancelled = false;
    const refresh = () => {
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
      void bridge
        .listUrls()
        .then((result) => {
          if (!cancelled) {
            setUrls(new Map(result.urls.map((url) => [url.id, url])));
          }
        })
        .catch(() => {
          // Degrade: a URL tile falls back to its id label, never breaks the row.
        });
      void bridge
        .listChromeProfiles()
        .then((result) => {
          if (cancelled) {
            return;
          }
          setProfilesByDir(new Map(result.profiles.map((profile) => [profile.directory, profile])));
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
  }, [bridge, key]);

  // The Chrome app icon (for pinned "Chrome — <profile>" refs), if discovery found it.
  const chromeIcon = [...discovered.values()].find((app) => app.bundleId === "com.google.Chrome")
    ?.iconPng;

  return (ref, fallbackLabel) => {
    const urlRef = urls.get(ref);
    const chromeRef = chromeRefsById.get(ref);
    const app = appDefinition(ref);
    const discoveredApp = discovered.get(ref);
    // A caller-supplied label (the layout session's authoritative resolved label)
    // wins; otherwise resolve it the same order Quick Apps does.
    const label =
      fallbackLabel ?? urlRef?.label ?? chromeRef?.label ?? app?.label ?? discoveredApp?.name ?? ref;
    const profileDir = urlRef?.profile ?? chromeRef?.profile;
    const profileAvatarPng = profileDir ? profilesByDir.get(profileDir)?.iconPng : undefined;

    if (urlRef) {
      return { label, iconPng: urlRef.iconPng, fallbackCategory: "browser", profileAvatarPng };
    }
    if (chromeRef) {
      return { label, iconPng: chromeIcon, fallbackCategory: "browser", profileAvatarPng };
    }
    return {
      label,
      iconPng: discoveredApp?.iconPng,
      fallbackCategory: app?.category ?? "files",
      profileAvatarPng
    };
  };
}
