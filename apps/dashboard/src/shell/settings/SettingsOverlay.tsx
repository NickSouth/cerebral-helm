import { useEffect, useRef, useState, type AnimationEvent, type KeyboardEvent } from "react";
import { useSettings } from "../../state/SettingsProvider";
import { SETTINGS_CATEGORIES } from "./categories";
import { SETTINGS_PANELS } from "./SettingsPanels";

/** Power glyph for the shutdown control. */
function PowerGlyph() {
  return (
    <svg
      viewBox="0 0 24 24"
      width="16"
      height="16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
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
/** Safety net for the exit phase: force the unmount if `animationend` never arrives. */
const EXIT_FALLBACK_MS = 400;

function SettingsWindow({ closing, onExited }: { closing: boolean; onExited: () => void }) {
  const { activeCategory, setCategory, closeSettings } = useSettings();
  const dialogRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    // Focus the window on open so Escape and Tab are captured; never auto-focus a mutating control.
    dialogRef.current?.focus();
  }, []);

  useEffect(() => {
    if (!closing) {
      return;
    }
    const dialog = dialogRef.current;
    // No Web Animations (jsdom) — unmount synchronously; close stays instant there.
    if (!dialog || typeof dialog.getAnimations !== "function") {
      onExited();
      return;
    }
    const fallback = window.setTimeout(onExited, EXIT_FALLBACK_MS);
    return () => window.clearTimeout(fallback);
  }, [closing, onExited]);

  function onKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.key === "Escape") {
      event.preventDefault();
      closeSettings();
    }
  }

  function onAnimationEnd(event: AnimationEvent<HTMLDivElement>) {
    // Only the window's own exit animation unmounts — never a child's or the entrance's.
    if (
      closing &&
      event.target === event.currentTarget &&
      event.animationName === "ch-settings-out"
    ) {
      onExited();
    }
  }

  const active =
    SETTINGS_CATEGORIES.find((category) => category.id === activeCategory) ??
    SETTINGS_CATEGORIES[0];
  const Panel = SETTINGS_PANELS[active.id];

  return (
    <>
      {/* Click-to-dismiss backdrop: a mouse convenience only. The keyboard-accessible dismiss
          paths are the dialog's Escape handler and the × close control, so the static-element
          click-handler rules are suppressed for the scrim. */}
      {/* eslint-disable-next-line jsx-a11y/click-events-have-key-events, jsx-a11y/no-static-element-interactions */}
      <div className="settings-scrim" data-closing={closing || undefined} onClick={closeSettings} />
      {/* A focusable modal dialog that captures Escape to close; onKeyDown on the dialog is the
          accessible pattern, so the non-interactive-element-interactions rule is suppressed. */}
      {/* eslint-disable-next-line jsx-a11y/no-noninteractive-element-interactions */}
      <div
        className="settings-window"
        data-closing={closing || undefined}
        role="dialog"
        aria-modal="true"
        aria-label="Settings"
        tabIndex={-1}
        ref={dialogRef}
        onKeyDown={onKeyDown}
        onAnimationEnd={onAnimationEnd}
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

/**
 * Overlay host slot: renders the settings window while it is open (view state), and keeps it
 * mounted through the exit animation — the window slides back into the bottom-right corner it
 * emerged from (settings.css) before unmounting. Environments without Web Animations unmount
 * immediately (SettingsWindow's exit effect), so close stays synchronous in tests.
 */
export function SettingsOverlay() {
  const { open } = useSettings();
  const [present, setPresent] = useState(open);

  if (open && !present) {
    // Render-phase sync so the window appears the same frame the gear is clicked.
    setPresent(true);
  }

  if (!open && !present) {
    return null;
  }

  return <SettingsWindow closing={!open} onExited={() => setPresent(false)} />;
}

export default SettingsOverlay;
