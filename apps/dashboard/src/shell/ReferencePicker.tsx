import {
  useEffect,
  useMemo,
  useRef,
  useState,
  type FormEvent,
  type KeyboardEvent
} from "react";
import { useBridge } from "../state/BridgeProvider";
import { useUiPosture } from "../state/useUiPosture";
import type { ChromeProfile } from "../bridge/cerebralBridge";
import { useDiscoveredApps } from "./useDiscoveredApps";
import { PickerSearchField } from "./PickerSearchField";
import { filterApps } from "./filterApps";
import { AppGlyph } from "./AppGlyph";

/** The kind of reference an "Add" resolves to (mirrors the layout schema). */
export type ReferenceKind = "app" | "url";

/**
 * The shared reference picker (NIC-142): the Quick Apps-style surface for choosing a
 * discovered app, a typed URL, or a Chrome profile. It owns discovery + the validated
 * URL/Chrome-profile minting, then hands the resolved reference id, kind, and label to
 * `onPick` — the caller decides what to do with it (add a session hotswap target, or add
 * a window to the layout being authored). Reuses the `pin-pop` styling so every "add a
 * window" surface reads the same.
 *
 * Two variants like {@link MoreAppsPicker}: `overlay` is the centered in-webview card with
 * a click-dismiss scrim; `standalone` fills its own native window. Stays open across adds.
 */
export function ReferencePicker({
  onPick,
  onClose,
  title,
  ariaLabel,
  variant = "overlay"
}: {
  onPick: (referenceId: string, kind: ReferenceKind, label: string) => void;
  onClose: () => void;
  title: string;
  ariaLabel: string;
  variant?: "overlay" | "standalone";
}) {
  const bridge = useBridge();
  const { readOnly } = useUiPosture();
  const cardRef = useRef<HTMLDivElement>(null);
  // Re-reads on `apps.changed`, so an app installed while this surface is open appears (NIC-175).
  const picker = useDiscoveredApps();
  const [busy, setBusy] = useState(false);
  const [writeError, setWriteError] = useState<string | null>(null);
  const [urlInput, setUrlInput] = useState("");
  const [urlLabel, setUrlLabel] = useState("");
  const [urlProfile, setUrlProfile] = useState("");
  const [urlError, setUrlError] = useState<string | null>(null);
  const [chromeProfiles, setChromeProfiles] = useState<readonly ChromeProfile[]>([]);
  const [query, setQuery] = useState("");

  // The search field takes mount focus instead of the card (NIC-167): this surface is summoned to
  // find one specific app, so the keyboard belongs in the filter. Escape still closes, because the
  // keydown bubbles from the input to the card's handler below.
  const visibleApps = useMemo(
    () => (picker.status === "ready" ? filterApps(picker.apps, query) : []),
    [picker, query]
  );

  useEffect(() => {
    let cancelled = false;
    bridge
      .listChromeProfiles()
      .then((result) => {
        if (!cancelled) {
          setChromeProfiles(result.profiles);
        }
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

  // Add a URL the same route Quick Apps does (NIC-146): mint the reference through the
  // validated auto-minting path, then hand the returned id to the caller.
  function addUrl(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const url = urlInput.trim();
    if (url.length === 0 || busy || readOnly) {
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
        onPick(result.reference.id, "url", result.reference.label);
      })
      .catch(() => setUrlError("The URL could not be added."))
      .finally(() => setBusy(false));
  }

  // Add "Chrome — <profile>" (NIC-151): mint the Chrome-profile app reference, then hand
  // the returned id to the caller — the same mint-then-use path a URL takes.
  function addChromeProfile(profile: ChromeProfile) {
    if (busy || readOnly) {
      return;
    }
    setBusy(true);
    setWriteError(null);
    bridge
      .addChromeProfileReference({ directory: profile.directory, name: profile.name })
      .then((result) => {
        if (!result.accepted || !result.reference) {
          setWriteError(result.errors[0] ?? "That Chrome profile couldn't be added.");
          return;
        }
        onPick(result.reference.id, "app", result.reference.label);
      })
      .catch(() => setWriteError("That Chrome profile couldn't be added."))
      .finally(() => setBusy(false));
  }

  const standalone = variant === "standalone";

  return (
    <>
      {standalone ? null : (
        // eslint-disable-next-line jsx-a11y/click-events-have-key-events, jsx-a11y/no-static-element-interactions
        <div className="pin-pop-scrim" onClick={onClose} />
      )}
      {/* eslint-disable-next-line jsx-a11y/no-noninteractive-element-interactions */}
      <div
        className={standalone ? "pin-pop pin-pop--standalone" : "pin-pop pin-pop--centered"}
        role="dialog"
        aria-modal="true"
        aria-label={ariaLabel}
        tabIndex={-1}
        ref={cardRef}
        onKeyDown={onKeyDown}
      >
        <header className="pin-pop__header">
          <h2 className="pin-pop__title">{title}</h2>
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
              disabled={busy || readOnly || urlInput.trim().length === 0}
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
                {chromeProfiles.map((profile) => (
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
                      aria-label={`Add Chrome — ${profile.name}`}
                      disabled={busy || readOnly}
                      onClick={() => addChromeProfile(profile)}
                    >
                      Add
                    </button>
                  </li>
                ))}
              </ul>
            </section>
          ) : null}

          <section className="pin-pop__section" aria-label="Applications">
            <h3 className="pin-pop__section-title">Applications</h3>
            {/* Scoped to this section on purpose: the Chrome-profile list above is short and fixed,
                and hiding it on an app query would surprise. */}
            <PickerSearchField value={query} onChange={setQuery} label="Search applications" />
            {picker.status === "loading" ? (
              <p className="pin-pop__note">Discovering installed applications…</p>
            ) : null}
            {picker.status === "error" ? <p className="pin-pop__note">{picker.message}</p> : null}
            {/* Distinguish "your search found nothing" from "this host has no apps" — collapsing
                them would blame the query for an empty inventory. */}
            {picker.status === "ready" && visibleApps.length === 0 ? (
              <p className="pin-pop__note">
                {query.trim().length > 0
                  ? `No applications match “${query.trim()}”.`
                  : "No applications found."}
              </p>
            ) : null}
            {picker.status === "ready" ? (
              <ul className="pin-pop__list">
                {visibleApps.map((app) => (
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
                      <button
                        type="button"
                        className="pin-pop__pin"
                        aria-label={`Add ${app.name}`}
                        disabled={busy || readOnly}
                        onClick={() => onPick(app.referenceId as string, "app", app.name)}
                      >
                        Add
                      </button>
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
      </div>
    </>
  );
}

export default ReferencePicker;
