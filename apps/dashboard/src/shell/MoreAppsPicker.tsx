import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import { useBridge } from "../state/BridgeProvider";
import { useDashboardState } from "../state/DashboardStateProvider";
import { useActiveMode } from "./useActiveMode";
import { useUiPosture } from "../state/useUiPosture";
import { toModeId } from "../tokens/tokens";
import type { DiscoveredApp } from "../bridge/cerebralBridge";
import { AppGlyph } from "./AppGlyph";

const MAX_QUICK_APPS = 5;

type PickerState =
  | { readonly status: "loading" }
  | { readonly status: "error"; readonly message: string }
  | { readonly status: "ready"; readonly apps: readonly DiscoveredApp[]; readonly truncated: boolean };

/**
 * The More Apps picker (NIC-119, NIC-149): installed applications from the
 * read-only `apps.list` discovery capability, with real OS icons where the
 * adapter could render one (the category glyph is the honest fallback).
 *
 * Launching (NIC-149): the picker is an alternate launcher — the app tile and
 * its Open control dispatch the same deterministic `open <referenceId>` command
 * as a pinned quick-app tile, gated on `native.app.open` like every launch
 * surface. An accepted launch closes the picker.
 *
 * Pinning (NIC-119c): a discovered app backed by a configured app reference can
 * be pinned into (or unpinned from) the active mode's five quick-app slots. The
 * write rides the validated config-override path — the bridge rejects unknown
 * references, and an accepted write emits `mode.quickapps.changed` so tiles
 * refresh everywhere. Apps without a configured reference say so honestly;
 * arbitrary paths can never enter the slots from here.
 */
export function MoreAppsPicker({ onClose }: { onClose: () => void }) {
  const bridge = useBridge();
  const state = useDashboardState();
  const { quickApps } = useActiveMode();
  const { readOnly } = useUiPosture();
  const modeId = toModeId(state.mode);
  const dialogRef = useRef<HTMLDivElement>(null);
  const [picker, setPicker] = useState<PickerState>({ status: "loading" });
  const [busy, setBusy] = useState(false);
  const [writeError, setWriteError] = useState<string | null>(null);
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
        // An accepted launch closes the picker — launcher semantics: the opened
        // app takes the foreground, the backdrop returns clean.
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

  function submitQuickApps(next: readonly string[]) {
    setBusy(true);
    setWriteError(null);
    bridge
      .updateQuickApps({ modeId, quickApps: next })
      .then((result) => {
        if (!result.accepted) {
          setWriteError(result.errors[0] ?? "The change was rejected by config validation.");
        }
        // An accepted write refreshes the tiles via the bridge's
        // mode.quickapps.changed event — no optimistic state here, the config
        // is the truth.
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
      return null;
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
                  <span className="apps-picker__actions">
                    <button
                      type="button"
                      className="apps-picker__open"
                      disabled={!canLaunch(app)}
                      title={launchTitle(app)}
                      onClick={() => launch(app)}
                    >
                      Open
                    </button>
                    {pinControl(app)}
                  </span>
                  {!app.referenceId ? (
                    <span className="apps-picker__unpinnable">Not a configured app reference</span>
                  ) : null}
                </li>
              ))}
            </ul>
            {launchError ? <p className="apps-picker__note">{launchError}</p> : null}
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
