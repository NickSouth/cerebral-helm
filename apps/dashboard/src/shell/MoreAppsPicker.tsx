import { useEffect, useRef, useState, type FormEvent, type KeyboardEvent } from "react";
import { useBridge } from "../state/BridgeProvider";
import { useDashboardState } from "../state/DashboardStateProvider";
import { useActiveMode } from "./useActiveMode";
import { useUiPosture } from "../state/useUiPosture";
import { toModeId } from "../tokens/tokens";
import type { ChromeProfile, DiscoveredApp } from "../bridge/cerebralBridge";
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
  const [urlInput, setUrlInput] = useState("");
  const [urlLabel, setUrlLabel] = useState("");
  const [urlProfile, setUrlProfile] = useState("");
  const [urlError, setUrlError] = useState<string | null>(null);
  // The user's Chrome profiles (NIC-151): populate the URL profile dropdown and the
  // "Open Chrome in a profile" pin section. Empty when Chrome isn't installed.
  const [chromeProfiles, setChromeProfiles] = useState<readonly ChromeProfile[]>([]);
  const [pinnedProfiles, setPinnedProfiles] = useState<ReadonlySet<string>>(new Set());

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

  // Load Chrome profiles for the dropdown + the pin section (NIC-151). Also tracks
  // which profiles are already pinned (by directory) so the section shows Pinned.
  useEffect(() => {
    let cancelled = false;
    bridge
      .listChromeProfiles()
      .then((result) => {
        if (cancelled) {
          return;
        }
        setChromeProfiles(result.profiles);
        setPinnedProfiles(
          new Set(result.references.map((ref) => ref.profile).filter((p): p is string => Boolean(p)))
        );
      })
      .catch(() => {
        // No profiles: the dropdown hides and the section shows nothing — degrade.
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

  // Add a URL the same route as pinning an app (NIC-146): mint the URL reference
  // through the validated auto-minting path, then pin the returned id into the
  // active mode. A pinned URL is just another quick-app tile (shared slots).
  function addUrl(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const url = urlInput.trim();
    if (url.length === 0 || busy || readOnly || slotsFull) {
      return;
    }
    setBusy(true);
    setUrlError(null);
    setWriteError(null);
    bridge
      .addUrlReference({
        url,
        label: urlLabel.trim() || undefined,
        profile: urlProfile.trim() || undefined
      })
      .then((result) => {
        if (!result.accepted || !result.reference) {
          setUrlError(result.errors[0] ?? "The URL could not be added.");
          return;
        }
        setUrlInput("");
        setUrlLabel("");
        setUrlProfile("");
        // Re-adding an already-pinned URL is a no-op pin (idempotent) — nothing to write.
        if (!quickApps.includes(result.reference.id)) {
          submitQuickApps([...quickApps, result.reference.id]);
        }
      })
      .catch(() => setUrlError("The URL could not be added."))
      .finally(() => setBusy(false));
  }

  // Pin "Chrome — <profile>" (NIC-151): mint the Chrome-profile app reference, then
  // pin the returned id into the active mode — the same mint-then-pin path a URL takes.
  function pinChromeProfile(profile: ChromeProfile) {
    if (busy || readOnly || slotsFull) {
      return;
    }
    setBusy(true);
    setWriteError(null);
    bridge
      .addChromeProfileReference({ directory: profile.directory, name: profile.name })
      .then((result) => {
        if (!result.accepted || !result.reference) {
          setWriteError(result.errors[0] ?? "That Chrome profile couldn't be pinned.");
          return;
        }
        setPinnedProfiles((prev) => new Set([...prev, profile.directory]));
        if (!quickApps.includes(result.reference.id)) {
          submitQuickApps([...quickApps, result.reference.id]);
        }
      })
      .catch(() => setWriteError("That Chrome profile couldn't be pinned."))
      .finally(() => setBusy(false));
  }

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
        {/* Add a URL as a quick app (NIC-146): the URL counterpart of pinning an app —
            it mints a reference and pins it to the active mode in one step. */}
        <form className="apps-picker__add-url" onSubmit={addUrl}>
          <label className="apps-picker__add-url-title" htmlFor="apps-picker-url">
            Add a URL
          </label>
          <div className="apps-picker__add-url-row">
            <input
              id="apps-picker-url"
              type="text"
              inputMode="url"
              className="apps-picker__add-url-field"
              placeholder="https://example.com"
              aria-label="URL"
              value={urlInput}
              onChange={(event) => setUrlInput(event.target.value)}
              disabled={busy || readOnly}
            />
            <input
              type="text"
              className="apps-picker__add-url-field apps-picker__add-url-field--name"
              placeholder="Name (optional)"
              aria-label="URL name (optional)"
              value={urlLabel}
              onChange={(event) => setUrlLabel(event.target.value)}
              disabled={busy || readOnly}
            />
            {/* Optional Chrome profile (NIC-151): a dropdown of the user's real Chrome
                profiles (display name shown, directory name sent). Hidden when Chrome
                exposes no profiles. Empty selection = default browser behavior. */}
            {chromeProfiles.length > 0 ? (
              <select
                className="apps-picker__add-url-field apps-picker__add-url-field--profile"
                aria-label="Chrome profile (optional)"
                value={urlProfile}
                onChange={(event) => setUrlProfile(event.target.value)}
                disabled={busy || readOnly}
              >
                <option value="">Default browser</option>
                {chromeProfiles.map((profile) => (
                  <option key={profile.directory} value={profile.directory}>
                    {`Chrome — ${profile.name}`}
                  </option>
                ))}
              </select>
            ) : null}
            <button
              type="submit"
              className="apps-picker__add-url-submit"
              disabled={busy || readOnly || slotsFull || urlInput.trim().length === 0}
              title={slotsFull ? "All five quick-app slots are full — unpin one first." : undefined}
            >
              Add
            </button>
          </div>
          {urlError ? <p className="apps-picker__note">{urlError}</p> : null}
          {slotsFull ? (
            <p className="apps-picker__note">
              All five quick-app slots are full — unpin one to add a URL.
            </p>
          ) : null}
        </form>
        {/* Open Chrome in a specific profile (NIC-151): each discovered profile is
            pinnable as its own quick app ("Chrome — Work"), avatar and all. */}
        {chromeProfiles.length > 0 ? (
          <section className="apps-picker__profiles" aria-label="Chrome profiles">
            <h3 className="apps-picker__profiles-title">Open Chrome in a profile</h3>
            <ul className="apps-picker__profiles-list">
              {chromeProfiles.map((profile) => {
                const alreadyPinned = pinnedProfiles.has(profile.directory);
                return (
                  <li key={profile.directory} className="apps-picker__profile">
                    <span className="apps-picker__profile-avatar" aria-hidden="true">
                      {profile.iconPng ? (
                        <img src={`data:image/png;base64,${profile.iconPng}`} alt="" />
                      ) : (
                        <AppGlyph category="browser" />
                      )}
                    </span>
                    <span className="apps-picker__profile-name">{`Chrome — ${profile.name}`}</span>
                    <button
                      type="button"
                      className="apps-picker__pin"
                      aria-label={
                        alreadyPinned
                          ? `Chrome — ${profile.name} already pinned`
                          : `Pin Chrome — ${profile.name}`
                      }
                      disabled={busy || readOnly || alreadyPinned || slotsFull}
                      title={
                        alreadyPinned
                          ? "Already pinned"
                          : slotsFull
                            ? "All five quick-app slots are full — unpin one first."
                            : undefined
                      }
                      onClick={() => pinChromeProfile(profile)}
                    >
                      {alreadyPinned ? "Pinned" : "Pin"}
                    </button>
                  </li>
                );
              })}
            </ul>
          </section>
        ) : null}
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
