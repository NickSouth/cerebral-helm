import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import { useBridge } from "../state/BridgeProvider";
import type { DiscoveredApp } from "../bridge/cerebralBridge";
import { AppGlyph } from "./AppGlyph";

type PickerState =
  | { readonly status: "loading" }
  | { readonly status: "error"; readonly message: string }
  | { readonly status: "ready"; readonly apps: readonly DiscoveredApp[]; readonly truncated: boolean };

/**
 * The More Apps picker (NIC-119): installed applications from the read-only
 * `apps.list` discovery capability, with real OS icons where the adapter could
 * render one (the category glyph is the honest fallback). Purely informational
 * this increment — it never launches anything, and pinning apps into slots
 * arrives with the validated config-write wiring (NIC-119c).
 */
export function MoreAppsPicker({ onClose }: { onClose: () => void }) {
  const bridge = useBridge();
  const dialogRef = useRef<HTMLDivElement>(null);
  const [state, setState] = useState<PickerState>({ status: "loading" });

  useEffect(() => {
    dialogRef.current?.focus();
  }, []);

  useEffect(() => {
    let cancelled = false;
    bridge
      .listApps()
      .then((result) => {
        if (!cancelled) {
          setState({ status: "ready", apps: result.apps, truncated: result.truncated });
        }
      })
      .catch(() => {
        if (!cancelled) {
          setState({ status: "error", message: "App discovery is unavailable right now." });
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

  return (
    <>
      {/* Click-to-dismiss scrim: a mouse convenience; Escape and × are the
          keyboard paths, so the static-element rules are suppressed. */}
      {/* eslint-disable-next-line jsx-a11y/click-events-have-key-events, jsx-a11y/no-static-element-interactions */}
      <div className="apps-picker-scrim" onClick={onClose} />
      {/* eslint-disable-next-line jsx-a11y/no-noninteractive-element-interactions */}
      <div
        className="apps-picker"
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
        {state.status === "loading" ? (
          <p className="apps-picker__note">Discovering installed applications…</p>
        ) : null}
        {state.status === "error" ? <p className="apps-picker__note">{state.message}</p> : null}
        {state.status === "ready" ? (
          <>
            <ul className="apps-picker__grid">
              {state.apps.map((app) => (
                <li key={app.bundleId} className="apps-picker__item" title={app.bundleId}>
                  <span className="apps-picker__icon" aria-hidden="true">
                    {app.iconPng ? (
                      <img src={`data:image/png;base64,${app.iconPng}`} alt="" />
                    ) : (
                      <AppGlyph category="files" />
                    )}
                  </span>
                  <span className="apps-picker__name">{app.name}</span>
                </li>
              ))}
            </ul>
            {state.truncated ? (
              <p className="apps-picker__note">Showing the first entries — the full list was capped.</p>
            ) : null}
            <p className="apps-picker__note">Pinning apps into slots arrives with the next increment.</p>
          </>
        ) : null}
      </div>
    </>
  );
}

export default MoreAppsPicker;
