import { useEffect, useState } from "react";
import { useBridge } from "../state/BridgeProvider";
import type { DiscoveredApp } from "../bridge/cerebralBridge";

/** The installed-app inventory as a surface sees it: loading, honestly unavailable, or ready. */
export type DiscoveredAppsState =
  | { readonly status: "loading" }
  | { readonly status: "error"; readonly message: string }
  | { readonly status: "ready"; readonly apps: readonly DiscoveredApp[]; readonly truncated: boolean };

/**
 * Read the installed-app inventory, and **keep it current** (NIC-175).
 *
 * Every surface that lists apps — More Apps, the pin popover, the layout pickers, the quick-app
 * tiles — used to read `listApps()` once on mount and never again. `listApps` re-scans on every
 * call, so reopening a surface always showed the truth; but a surface that was *already open* when
 * an app was installed kept showing the old inventory until it was closed and reopened. Subscribing
 * to `apps.changed` closes that gap: the native watcher fires once the Applications folder settles
 * (which, for a large app, is also when its copy finishes and its bundle finally loads), and every
 * open surface re-reads.
 *
 * Living in one hook rather than in each surface means a new app list gets this behaviour by
 * construction instead of by remembering.
 *
 * `enabled` is for surfaces that gate on the discovery capability (the quick-app tiles): when
 * false nothing is fetched and nothing is subscribed, and the state stays `loading` — the caller
 * already renders its own fallback in that case.
 */
export function useDiscoveredApps(enabled = true): DiscoveredAppsState {
  const bridge = useBridge();
  const [state, setState] = useState<DiscoveredAppsState>({ status: "loading" });

  useEffect(() => {
    if (!enabled) {
      return;
    }
    let cancelled = false;

    const read = () => {
      bridge
        .listApps()
        .then((result) => {
          if (cancelled) {
            return;
          }
          setState({ status: "ready", apps: result.apps, truncated: result.truncated });
        })
        .catch(() => {
          if (cancelled) {
            return;
          }
          setState({ status: "error", message: "App discovery is unavailable right now." });
        });
    };

    read();
    const unsubscribe = bridge.subscribe((event) => {
      if (event.type === "apps.changed") {
        read();
      }
    });

    return () => {
      cancelled = true;
      unsubscribe();
    };
  }, [bridge, enabled]);

  return state;
}
