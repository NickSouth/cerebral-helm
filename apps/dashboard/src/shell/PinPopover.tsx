import {
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type FormEvent,
  type KeyboardEvent
} from "react";
import { createPortal } from "react-dom";
import { useBridge } from "../state/BridgeProvider";
import { useDashboardState } from "../state/DashboardStateProvider";
import { useActiveMode } from "./useActiveMode";
import { useUiPosture } from "../state/useUiPosture";
import { toModeId } from "../tokens/tokens";
import type { AppReference, ChromeProfile, DiscoveredApp } from "../bridge/cerebralBridge";
import { useDiscoveredApps } from "./useDiscoveredApps";
import { AppGlyph } from "./AppGlyph";

const MAX_QUICK_APPS = 5;

interface PopoverPosition {
  readonly left: number;
  readonly top: number;
  readonly wedge: number;
}

/**
 * The pin popover (NIC-148): the single surface that *pins* into an empty quick-app
 * slot. Split out of the old combined picker so pinning and launching are distinct
 * jobs — More Apps launches, this pins. It owns every pin route: a discovered app
 * (NIC-119c), a typed URL (NIC-146), or a Chrome profile (NIC-151). Every write
 * rides the validated config-override path; the bridge rejects unknown references,
 * and an accepted write emits `mode.quickapps.changed` so tiles refresh.
 *
 * It renders through a portal, anchored under the clicked empty slot with a wedge
 * pointing at it (an in-webview overlay by owner decision — small and slot-tied, it
 * never needs to rise above other apps the way the launcher window does). Pins
 * left-fill the slots, so which empty slot was clicked only drives the anchor, not
 * the target position.
 */
export function PinPopover({ anchor, onClose }: { anchor: HTMLElement; onClose: () => void }) {
  const bridge = useBridge();
  const state = useDashboardState();
  const { quickApps } = useActiveMode();
  const { readOnly } = useUiPosture();
  const modeId = toModeId(state.mode);
  const cardRef = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState<PopoverPosition | null>(null);
  // Re-reads on `apps.changed`, so an app installed while this surface is open appears (NIC-175).
  const picker = useDiscoveredApps();
  const [busy, setBusy] = useState(false);
  const [writeError, setWriteError] = useState<string | null>(null);
  const [urlInput, setUrlInput] = useState("");
  const [urlLabel, setUrlLabel] = useState("");
  const [urlProfile, setUrlProfile] = useState("");
  const [urlError, setUrlError] = useState<string | null>(null);
  const [chromeProfiles, setChromeProfiles] = useState<readonly ChromeProfile[]>([]);
  // The user's Chrome-profile references are a GLOBAL catalog (a profile pinned in
  // any mode mints one reference), so "already pinned" must be judged against THIS
  // mode's quickApps — never the mere existence of a reference — otherwise a profile
  // pinned in one mode reads as pinned everywhere (NIC-148 fix).
  const [profileRefs, setProfileRefs] = useState<readonly AppReference[]>([]);
  const dirByRef = new Map(profileRefs.map((ref) => [ref.id, ref.profile]));
  const pinnedDirsInMode = new Set(
    quickApps.map((id) => dirByRef.get(id)).filter((dir): dir is string => Boolean(dir))
  );

  // Anchor the card under the clicked slot with a wedge pointing at it. Fixed
  // (viewport) coordinates via a portal so no ancestor's overflow can clip it, and
  // recomputed on resize. jsdom returns zeroed rects — the card still renders, just
  // at the origin, which is all the tests need.
  useLayoutEffect(() => {
    function place() {
      const card = cardRef.current;
      if (!card) {
        return;
      }
      const a = anchor.getBoundingClientRect();
      const cardW = card.offsetWidth;
      const anchorCenter = a.left + a.width / 2;
      const maxLeft = Math.max(8, window.innerWidth - cardW - 8);
      const left = Math.min(Math.max(8, anchorCenter - cardW / 2), maxLeft);
      const wedge = Math.min(Math.max(12, anchorCenter - left), Math.max(12, cardW - 12));
      setPos({ left, top: a.bottom + 8, wedge });
    }
    place();
    window.addEventListener("resize", place);
    return () => window.removeEventListener("resize", place);
  }, [anchor]);

  useEffect(() => {
    cardRef.current?.focus();
  }, []);

  useEffect(() => {
    let cancelled = false;
    bridge
      .listChromeProfiles()
      .then((result) => {
        if (cancelled) {
          return;
        }
        setChromeProfiles(result.profiles);
        setProfileRefs(result.references);
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

  const slotsFull = quickApps.length >= MAX_QUICK_APPS;

  function submitQuickApps(next: readonly string[]) {
    setBusy(true);
    setWriteError(null);
    bridge
      .updateQuickApps({ modeId, quickApps: next })
      .then((result) => {
        if (!result.accepted) {
          setWriteError(result.errors[0] ?? "The change was rejected by config validation.");
        }
        // An accepted write refreshes the tiles via mode.quickapps.changed — the
        // config is the truth, no optimistic state here.
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

  // Add a URL the same route as pinning an app (NIC-146): mint the reference through
  // the validated auto-minting path, then pin the returned id into the active mode.
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
        // Re-adding an already-pinned URL is a no-op pin (idempotent).
        if (!quickApps.includes(result.reference.id)) {
          submitQuickApps([...quickApps, result.reference.id]);
        }
      })
      .catch(() => setUrlError("The URL could not be added."))
      .finally(() => setBusy(false));
  }

  // Pin "Chrome — <profile>" (NIC-151): mint the Chrome-profile app reference, then
  // pin the returned id — the same mint-then-pin path a URL takes.
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
        // Learn the minted reference so `pinnedDirsInMode` recognizes it the moment
        // the quickApps write lands (the ref may be brand new to this catalog).
        const minted = result.reference;
        setProfileRefs((prev) => (prev.some((ref) => ref.id === minted.id) ? prev : [...prev, minted]));
        if (!quickApps.includes(minted.id)) {
          submitQuickApps([...quickApps, minted.id]);
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
        <button type="button" className="pin-pop__pin" disabled={busy} onClick={() => unpin(referenceId)}>
          Unpin
        </button>
      );
    }
    return (
      <button
        type="button"
        className="pin-pop__pin"
        disabled={busy || slotsFull}
        title={slotsFull ? "All five quick-app slots are full — unpin one first." : undefined}
        onClick={() => pin(referenceId)}
      >
        Pin
      </button>
    );
  }

  return createPortal(
    <>
      {/* Click-to-dismiss catcher; Escape and × are the keyboard paths. */}
      {/* eslint-disable-next-line jsx-a11y/click-events-have-key-events, jsx-a11y/no-static-element-interactions */}
      <div className="pin-pop-scrim" onClick={onClose} />
      {/* eslint-disable-next-line jsx-a11y/no-noninteractive-element-interactions */}
      <div
        className="pin-pop"
        role="dialog"
        aria-modal="true"
        aria-label="Pin an app"
        tabIndex={-1}
        ref={cardRef}
        onKeyDown={onKeyDown}
        style={
          pos
            ? { left: pos.left, top: pos.top, visibility: "visible" }
            : { left: 0, top: 0, visibility: "hidden" }
        }
      >
        <span className="pin-pop__wedge" style={pos ? { left: pos.wedge } : undefined} aria-hidden="true" />
        <header className="pin-pop__header">
          <h2 className="pin-pop__title">Pin to this slot</h2>
          <button type="button" className="pin-pop__close" aria-label="Close pin menu" onClick={onClose}>
            ×
          </button>
        </header>

        <form className="pin-pop__add-url" onSubmit={addUrl}>
          <div className="pin-pop__add-url-row">
            <input
              type="text"
              inputMode="url"
              className="pin-pop__field pin-pop__field--url"
              placeholder="https://example.com"
              aria-label="URL"
              value={urlInput}
              onChange={(event) => setUrlInput(event.target.value)}
              disabled={busy || readOnly}
            />
            <button
              type="submit"
              className="pin-pop__add-url-submit"
              disabled={busy || readOnly || slotsFull || urlInput.trim().length === 0}
              title={slotsFull ? "All five quick-app slots are full — unpin one first." : undefined}
            >
              Add
            </button>
          </div>
          <div className="pin-pop__add-url-row">
            <input
              type="text"
              className="pin-pop__field"
              placeholder="Name (optional)"
              aria-label="URL name (optional)"
              value={urlLabel}
              onChange={(event) => setUrlLabel(event.target.value)}
              disabled={busy || readOnly}
            />
            {chromeProfiles.length > 0 ? (
              <select
                className="pin-pop__field"
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
          </div>
          {urlError ? <p className="pin-pop__note">{urlError}</p> : null}
        </form>

        <div className="pin-pop__scroll">
          {chromeProfiles.length > 0 ? (
            <section className="pin-pop__section" aria-label="Chrome profiles">
              <h3 className="pin-pop__section-title">Chrome profiles</h3>
              <ul className="pin-pop__list">
                {chromeProfiles.map((profile) => {
                  const alreadyPinned = pinnedDirsInMode.has(profile.directory);
                  return (
                    <li key={profile.directory} className="pin-pop__row">
                      <span className="pin-pop__avatar" aria-hidden="true">
                        {profile.iconPng ? (
                          <img src={`data:image/png;base64,${profile.iconPng}`} alt="" />
                        ) : (
                          <AppGlyph category="browser" />
                        )}
                      </span>
                      <span className="pin-pop__name">{`Chrome — ${profile.name}`}</span>
                      <button
                        type="button"
                        className="pin-pop__pin"
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

          <section className="pin-pop__section" aria-label="Applications">
            <h3 className="pin-pop__section-title">Applications</h3>
            {picker.status === "loading" ? (
              <p className="pin-pop__note">Discovering installed applications…</p>
            ) : null}
            {picker.status === "error" ? <p className="pin-pop__note">{picker.message}</p> : null}
            {picker.status === "ready" ? (
              <ul className="pin-pop__list">
                {picker.apps.map((app) => (
                  <li key={app.bundleId} className="pin-pop__row" title={app.bundleId}>
                    <span className="pin-pop__avatar" aria-hidden="true">
                      {app.iconPng ? (
                        <img src={`data:image/png;base64,${app.iconPng}`} alt="" />
                      ) : (
                        <AppGlyph category="files" />
                      )}
                    </span>
                    <span className="pin-pop__name">{app.name}</span>
                    {app.referenceId ? (
                      pinControl(app)
                    ) : (
                      <span className="pin-pop__unpinnable">Not a configured app reference</span>
                    )}
                  </li>
                ))}
              </ul>
            ) : null}
          </section>
        </div>

        {writeError ? <p className="pin-pop__note">{writeError}</p> : null}
        {slotsFull ? (
          <p className="pin-pop__note">All five quick-app slots are full — unpin one to add another.</p>
        ) : null}
      </div>
    </>,
    document.body
  );
}

export default PinPopover;
