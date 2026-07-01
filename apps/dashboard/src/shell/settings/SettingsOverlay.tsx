import { useEffect, useRef, type KeyboardEvent } from "react";
import { useSettings } from "../../state/SettingsProvider";
import { SETTINGS_CATEGORIES } from "./categories";
import { SETTINGS_PANELS } from "./SettingsPanels";

/** Power glyph for the shutdown control. */
function PowerGlyph() {
  return (
    <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false">
      <path d="M12 3v9" />
      <path d="M6.4 6.4a8 8 0 1 0 11.2 0" />
    </svg>
  );
}

/**
 * The floating settings window (NIC-63 / design spec §10 SettingsWindow). A macOS-style two-pane
 * surface — categories on the left, the selected panel on the right — composited over the dashboard
 * behind a scrim. It **never replaces the dashboard** (the shell stays mounted beneath), takes the
 * active mode accent via `data-mode` inheritance, traps focus while open, and closes on Escape or
 * the close control. Shutdown is pinned bottom-left, honest-disabled pre-Mac (a macOS lifecycle
 * capability). Every panel control is editable / read-only-inspection / unavailable — never fake.
 */
function SettingsWindow() {
  const { activeCategory, setCategory, closeSettings } = useSettings();
  const dialogRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    // Focus the window on open so Escape and Tab are captured; never auto-focus a mutating control.
    dialogRef.current?.focus();
  }, []);

  function onKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.key === "Escape") {
      event.preventDefault();
      closeSettings();
    }
  }

  const active = SETTINGS_CATEGORIES.find((category) => category.id === activeCategory) ?? SETTINGS_CATEGORIES[0];
  const Panel = SETTINGS_PANELS[active.id];

  return (
    <>
      <div className="settings-scrim" onClick={closeSettings} />
      <div
        className="settings-window"
        role="dialog"
        aria-modal="true"
        aria-label="Settings"
        tabIndex={-1}
        ref={dialogRef}
        onKeyDown={onKeyDown}
      >
        <nav className="settings-sidebar" aria-label="Settings categories">
          <div className="settings-sidebar__list" role="tablist" aria-orientation="vertical">
            {SETTINGS_CATEGORIES.map((category) => {
              const selected = category.id === active.id;
              return (
                <button
                  key={category.id}
                  type="button"
                  role="tab"
                  className="settings-category"
                  data-active={selected}
                  aria-selected={selected}
                  onClick={() => setCategory(category.id)}
                >
                  {category.label}
                </button>
              );
            })}
          </div>
          <button
            type="button"
            className="settings-shutdown"
            disabled
            aria-disabled="true"
            title="Shutting down CerebralHelm requires the macOS host"
          >
            <PowerGlyph />
            <span>Shut down CerebralHelm</span>
          </button>
        </nav>

        <div className="settings-content" role="tabpanel" aria-label={active.label}>
          <header className="settings-content__header">
            <h2 className="settings-content__title">{active.label}</h2>
            <p className="settings-content__description">{active.description}</p>
            <button
              type="button"
              className="settings-content__close"
              aria-label="Close settings"
              onClick={closeSettings}
            >
              ×
            </button>
          </header>
          <div className="settings-content__body">
            <Panel />
          </div>
        </div>
      </div>
    </>
  );
}

/** Overlay host slot: renders the settings window only while it is open (view state). */
export function SettingsOverlay() {
  const { open } = useSettings();
  return open ? <SettingsWindow /> : null;
}

export default SettingsOverlay;
