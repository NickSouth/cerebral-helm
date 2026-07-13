import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import { useBridge } from "../state/BridgeProvider";
import { useDashboardState } from "../state/DashboardStateProvider";
import { useUiPosture } from "../state/useUiPosture";
import type { DiscoveredApp } from "../bridge/cerebralBridge";
import { AppGlyph } from "./AppGlyph";

type PickerState =
  | { readonly status: "loading" }
  | { readonly status: "error"; readonly message: string }
  | { readonly status: "ready"; readonly apps: readonly DiscoveredApp[]; readonly truncated: boolean };

/**
 * The More Apps window (NIC-148): a pure launcher over the read-only `apps.list`
 * discovery capability (NIC-119). Split from the old combined picker — pinning
 * moved to {@link PinPopover}, this surface only *opens* apps. Each entry dispatches
 * the deterministic `open <referenceId>` command (FR-CMD-01), gated on
 * `native.app.open`; an accepted launch closes the window (launcher semantics,
 * NIC-149) so the opened app takes the foreground and the backdrop returns clean.
 *
 * The window is tall and two-wide (owner decision) so scrolling reveals more, and
 * wears a CerebralHelm-themed bar with a themed × rather than native chrome.
 *
 * Two variants (NIC-148): `overlay` is the centered in-webview card with a
 * click-dismiss scrim — the browser-preview fallback when there's no native shell.
 * `standalone` fills its own top-most native window (`index.html?surface=moreapps`),
 * so it drops the scrim and centering and lets the window chrome frame it. Both
 * dispatch the same `open <id>` and close on an accepted launch (`onClose`), which
 * in the standalone surface asks the native shell to close the window.
 */
export function MoreAppsPicker({
  onClose,
  variant = "overlay"
}: {
  onClose: () => void;
  variant?: "overlay" | "standalone";
}) {
  const bridge = useBridge();
  const state = useDashboardState();
  const { readOnly } = useUiPosture();
  const dialogRef = useRef<HTMLDivElement>(null);
  const [picker, setPicker] = useState<PickerState>({ status: "loading" });
  const [launchError, setLaunchError] = useState<string | null>(null);

  const appOpen = state.capabilities?.["native.app.open"];
  const openAvailable = appOpen?.available === true && !readOnly;
  const openUnavailableReason = readOnly
    ? "Unavailable while the app is in read-only recovery"
    : (appOpen?.degradedReason ?? "Launching apps is available on the macOS host");

  useEffect(() => {
    dialogRef.current?.focus();
  }, []);

  useEffect(() => {
    let cancelled = false;
    bridge
      .listApps()
      .then((result) => {
        if (!cancelled) {
          setPicker({ status: "ready", apps: result.apps, truncated: result.truncated });
        }
      })
      .catch(() => {
        if (!cancelled) {
          setPicker({ status: "error", message: "App discovery is unavailable right now." });
        }
      });
    return () => {
      cancelled = true;
    };
  }, [bridge]);

  function onKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.key === "Escape") {
      event.preventDefault();
      onClose();
    }
  }

  function launch(app: DiscoveredApp) {
    if (!app.referenceId) {
      return;
    }
    const { name, referenceId } = app;
    setLaunchError(null);
    bridge
      .submitCommand({ rawInput: `open ${referenceId}`, source: "dashboard" })
      .then((receipt) => {
        if (!receipt.accepted) {
          setLaunchError(`I couldn't open ${name} — it isn't a configured app reference.`);
          return;
        }
        // Opening an app closes the window — it doesn't need to persist (NIC-148).
        onClose();
      })
      .catch(() => {
        setLaunchError(`Opening ${name} failed — the bridge did not accept the command.`);
      });
  }

  function canLaunch(app: DiscoveredApp): boolean {
    return openAvailable && Boolean(app.referenceId);
  }

  function launchTitle(app: DiscoveredApp): string {
    if (!app.referenceId) {
      return "Not a configured app reference";
    }
    return openAvailable ? `Open ${app.name}` : openUnavailableReason;
  }

  const standalone = variant === "standalone";

  return (
    <>
      {/* Click-to-dismiss scrim: a mouse convenience only in the overlay variant;
          Escape and × are the keyboard paths, so the static-element rules are
          suppressed. The standalone window has no scrim — it IS the window. */}
      {standalone ? null : (
        // eslint-disable-next-line jsx-a11y/click-events-have-key-events, jsx-a11y/no-static-element-interactions
        <div className="apps-picker-scrim" onClick={onClose} />
      )}
      {/* eslint-disable-next-line jsx-a11y/no-noninteractive-element-interactions */}
      <div
        className={standalone ? "apps-picker apps-picker--standalone" : "apps-picker"}
        role="dialog"
        aria-modal="true"
        aria-label="All applications"
        tabIndex={-1}
        ref={dialogRef}
        onKeyDown={onKeyDown}
      >
        <header className="apps-picker__header">
          <h2 className="apps-picker__title">All applications</h2>
          <button
            type="button"
            className="apps-picker__close"
            aria-label="Close application list"
            onClick={onClose}
          >
            ×
          </button>
        </header>
        {picker.status === "loading" ? (
          <p className="apps-picker__note">Discovering installed applications…</p>
        ) : null}
        {picker.status === "error" ? <p className="apps-picker__note">{picker.message}</p> : null}
        {picker.status === "ready" ? (
          <>
            <ul className="apps-picker__grid">
              {picker.apps.map((app) => (
                <li key={app.bundleId} className="apps-picker__item" title={app.bundleId}>
                  <button
                    type="button"
                    className="apps-picker__launch"
                    disabled={!canLaunch(app)}
                    aria-disabled={!canLaunch(app)}
                    title={launchTitle(app)}
                    onClick={() => launch(app)}
                  >
                    <span className="apps-picker__icon" aria-hidden="true">
                      {app.iconPng ? (
                        <img src={`data:image/png;base64,${app.iconPng}`} alt="" />
                      ) : (
                        <AppGlyph category="files" />
                      )}
                    </span>
                    <span className="apps-picker__name">{app.name}</span>
                  </button>
                </li>
              ))}
            </ul>
            {launchError ? <p className="apps-picker__note">{launchError}</p> : null}
            {picker.truncated ? (
              <p className="apps-picker__note">Showing the first entries — the full list was capped.</p>
            ) : null}
          </>
        ) : null}
      </div>
    </>
  );
}

export default MoreAppsPicker;
