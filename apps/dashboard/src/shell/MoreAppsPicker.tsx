import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import { useBridge } from "../state/BridgeProvider";
import { useDashboardState } from "../state/DashboardStateProvider";
import { useActiveMode } from "./useActiveMode";
import { toModeId } from "../tokens/tokens";
import type { DiscoveredApp } from "../bridge/cerebralBridge";
import { AppGlyph } from "./AppGlyph";

const MAX_QUICK_APPS = 5;

type PickerState =
  | { readonly status: "loading" }
  | { readonly status: "error"; readonly message: string }
  | { readonly status: "ready"; readonly apps: readonly DiscoveredApp[]; readonly truncated: boolean };

/**
 * The More Apps picker (NIC-119): installed applications from the read-only
 * `apps.list` discovery capability, with real OS icons where the adapter could
 * render one (the category glyph is the honest fallback). It never launches
 * anything.
 *
 * Pinning (NIC-119c): a discovered app backed by a configured app reference can
 * be pinned into (or unpinned from) the active mode's five quick-app slots. The
 * write rides the validated config-override path — the bridge rejects unknown
 * references, and an accepted write re-emits the mode snapshot so tiles refresh
 * everywhere. Apps without a configured reference say so honestly; arbitrary
 * paths can never enter the slots from here.
 */
export function MoreAppsPicker({ onClose }: { onClose: () => void }) {
  const bridge = useBridge();
  const state = useDashboardState();
  const { quickApps } = useActiveMode();
  const modeId = toModeId(state.mode);
  const dialogRef = useRef<HTMLDivElement>(null);
  const [picker, setPicker] = useState<PickerState>({ status: "loading" });
  const [busy, setBusy] = useState(false);
  const [writeError, setWriteError] = useState<string | null>(null);

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

  function submitQuickApps(next: readonly string[]) {
    setBusy(true);
    setWriteError(null);
    bridge
      .updateQuickApps({ modeId, quickApps: next })
      .then((result) => {
        if (!result.accepted) {
          setWriteError(result.errors[0] ?? "The change was rejected by config validation.");
        }
        // An accepted write refreshes the tiles via the bridge's config.changed
        // snapshot — no optimistic state here, the config is the truth.
      })
      .catch(() => {
        setWriteError("The change could not be written.");
      })
      .finally(() => setBusy(false));
  }

  function pin(referenceId: string) {
    submitQuickApps([...quickApps, referenceId]);
  }

  function unpin(referenceId: string) {
    submitQuickApps(quickApps.filter((id) => id !== referenceId));
  }

  const slotsFull = quickApps.length >= MAX_QUICK_APPS;

  function pinControl(app: DiscoveredApp) {
    if (!app.referenceId) {
      return <span className="apps-picker__unpinnable">Not a configured app reference</span>;
    }
    const referenceId = app.referenceId;
    if (quickApps.includes(referenceId)) {
      return (
        <button
          type="button"
          className="apps-picker__pin"
          disabled={busy}
          onClick={() => unpin(referenceId)}
        >
          Unpin
        </button>
      );
    }
    return (
      <button
        type="button"
        className="apps-picker__pin"
        disabled={busy || slotsFull}
        title={slotsFull ? "All five quick-app slots are full — unpin one first." : undefined}
        onClick={() => pin(referenceId)}
      >
        Pin
      </button>
    );
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
        {picker.status === "loading" ? (
          <p className="apps-picker__note">Discovering installed applications…</p>
        ) : null}
        {picker.status === "error" ? <p className="apps-picker__note">{picker.message}</p> : null}
        {picker.status === "ready" ? (
          <>
            <ul className="apps-picker__grid">
              {picker.apps.map((app) => (
                <li key={app.bundleId} className="apps-picker__item" title={app.bundleId}>
                  <span className="apps-picker__icon" aria-hidden="true">
                    {app.iconPng ? (
                      <img src={`data:image/png;base64,${app.iconPng}`} alt="" />
                    ) : (
                      <AppGlyph category="files" />
                    )}
                  </span>
                  <span className="apps-picker__name">{app.name}</span>
                  {pinControl(app)}
                </li>
              ))}
            </ul>
            {writeError ? <p className="apps-picker__note">{writeError}</p> : null}
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
