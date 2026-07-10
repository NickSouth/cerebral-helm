import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import { BeamOverlay } from "./BeamOverlay";
import { rankSuggestions } from "./commandSuggestions";

/** Magnifying-glass glyph for the persistent launcher. */
function SearchGlyph() {
  return (
    <svg
      className="global-search__glyph"
      viewBox="0 0 24 24"
      width="18"
      height="18"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <circle cx="11" cy="11" r="6.5" />
      <path d="M20 20l-4.3-4.3" />
    </svg>
  );
}

/**
 * The shared command/search input. Used as the persistent top **launcher** (C0 — global, always
 * visible) on the dashboard and inside the floating command palette. Suggestions are
 * capability-aware and command-matching only; unavailable actions are shown disabled (NIC-58).
 * The Heimlich "Ask" affordance was removed with the chat surface (NIC-124) — free text that
 * matches no command is still submittable (it reports the honest not-implemented state), but it
 * is no longer offered as a suggestion.
 */
export function CommandSurface({
  variant,
  placeholder,
  ariaLabel,
  onSubmit,
  disabled = false,
  focusOnMount = false,
  spotlight = false
}: {
  variant: "launcher" | "docked";
  placeholder: string;
  ariaLabel: string;
  onSubmit: (text: string) => void;
  /** Suppress the command locus while the surface is read-only (offline/recovery — NIC-64). */
  disabled?: boolean;
  /**
   * Move focus into the input on mount — used by the floating command palette (NIC-75).
   * Implemented as an effect (the WAI-ARIA pattern for a just-summoned surface) rather than the
   * DOM autoFocus attribute, which jsx-a11y rightly flags for ordinary page content.
   */
  focusOnMount?: boolean;
  /**
   * Spotlight mode (NIC-77): show the suggestion list only once the user has typed something,
   * so an empty focus is just the bare search bar. Used by the floating palette; the docked
   * top launcher leaves this off and still surfaces suggestions on focus.
   */
  spotlight?: boolean;
}) {
  const [value, setValue] = useState("");
  const [focused, setFocused] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (focusOnMount) {
      inputRef.current?.focus();
    }
  }, [focusOnMount]);

  function submit(text: string): void {
    if (disabled) {
      return;
    }
    const trimmed = text.trim();
    if (!trimmed) {
      return;
    }
    onSubmit(trimmed);
    setValue("");
    setFocused(false);
  }

  function onKeyDown(event: KeyboardEvent<HTMLInputElement>): void {
    if (event.key === "Enter") {
      event.preventDefault();
      submit(value);
    } else if (event.key === "Escape") {
      setFocused(false);
    }
  }

  const trimmed = value.trim();
  const suggestions = rankSuggestions(value);
  // Only the global launcher surfaces the suggestion list. A read-only surface never shows
  // actionable suggestions. In spotlight mode (the floating palette) the list stays hidden until
  // the user types. With the "Ask Heimlich" row gone (NIC-124), an empty match set shows nothing.
  const showSuggestions =
    focused &&
    variant === "launcher" &&
    !disabled &&
    (!spotlight || trimmed.length > 0) &&
    suggestions.length > 0;

  return (
    <div
      className={`command-surface command-surface--${variant}`}
      data-disabled={disabled || undefined}
    >
      {variant === "launcher" ? (
        <span className="global-search__icon" aria-hidden="true">
          <SearchGlyph />
        </span>
      ) : null}
      <input
        ref={inputRef}
        type="text"
        className={variant === "launcher" ? "global-search__input" : "docked-input__input"}
        value={value}
        placeholder={disabled ? "Paused — the dashboard is read-only" : placeholder}
        aria-label={ariaLabel}
        disabled={disabled}
        /* A command input, not prose: macOS/WebKit autocorrect + inline writing suggestions
           otherwise draw a native completion bubble OVER the input (NIC-77 palette overlap). */
        autoComplete="off"
        autoCorrect="off"
        autoCapitalize="off"
        spellCheck={false}
        {...({ writingsuggestions: "false" } as Record<string, string>)}
        onChange={(event) => {
          setValue(event.target.value);
          // Typing IS focus: after a dismiss (submit/Escape) the pre-warmed palette's input can
          // still be document.activeElement, so the next summon's .focus() fires no event and the
          // `focused` state stays stale-false — which silently suppressed suggestions (NIC-77).
          setFocused(true);
        }}
        onFocus={() => setFocused(true)}
        onBlur={() => setFocused(false)}
        onKeyDown={onKeyDown}
      />
      {showSuggestions ? (
        <ul className="command-suggestions" aria-label="Command suggestions">
          {suggestions.map((suggestion) => (
            <li key={suggestion.id}>
              <button
                type="button"
                className="command-suggestion"
                disabled={!suggestion.available}
                aria-disabled={!suggestion.available}
                title={suggestion.hint}
                onMouseDown={(event) => {
                  event.preventDefault();
                  if (suggestion.available) {
                    submit(suggestion.label);
                  }
                }}
              >
                {suggestion.label}
                {suggestion.available ? null : (
                  <span className="command-suggestion__badge">unavailable</span>
                )}
              </button>
            </li>
          ))}
        </ul>
      ) : null}
      {/* Only the launcher carries the beam ring (matching its outline styling). */}
      {variant === "launcher" ? <BeamOverlay /> : null}
    </div>
  );
}
