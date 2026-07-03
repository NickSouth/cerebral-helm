import { useState, type KeyboardEvent } from "react";
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
 * The shared command/search input, used in two distinct placements (course-correction C):
 * the persistent top **launcher** (C0 — global, always visible, "Ask Heimlich first") and the
 * in-conversation **docked** input (continues the current exchange). One input model, two
 * roles — not two duplicate searches, and no floating command-palette modal. Suggestions are
 * capability-aware; unknown text always offers "Ask Heimlich"; unavailable actions are shown
 * disabled (NIC-58).
 */
export function CommandSurface({
  variant,
  placeholder,
  ariaLabel,
  onSubmit,
  disabled = false,
  autoFocus = false,
  spotlight = false
}: {
  variant: "launcher" | "docked";
  placeholder: string;
  ariaLabel: string;
  onSubmit: (text: string) => void;
  /** Suppress the command locus while the surface is read-only (offline/recovery — NIC-64). */
  disabled?: boolean;
  /** Focus the input on mount — used by the floating command palette (NIC-75). */
  autoFocus?: boolean;
  /**
   * Spotlight mode (NIC-77): show the suggestion list only once the user has typed something,
   * so an empty focus is just the bare search bar. Used by the floating palette; the docked
   * top launcher leaves this off and still surfaces suggestions on focus.
   */
  spotlight?: boolean;
}) {
  const [value, setValue] = useState("");
  const [focused, setFocused] = useState(false);

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
  // Only the global launcher surfaces the suggestion list; the docked input continues the
  // current exchange directly. A read-only surface never shows actionable suggestions. In
  // spotlight mode (the floating palette) the list stays hidden until the user types.
  const showSuggestions =
    focused && variant === "launcher" && !disabled && (!spotlight || trimmed.length > 0);
  const suggestions = rankSuggestions(value);

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
        type="text"
        className={variant === "launcher" ? "global-search__input" : "docked-input__input"}
        value={value}
        placeholder={disabled ? "Paused — the dashboard is read-only" : placeholder}
        aria-label={ariaLabel}
        disabled={disabled}
        autoFocus={autoFocus}
        onChange={(event) => setValue(event.target.value)}
        onFocus={() => setFocused(true)}
        onBlur={() => setFocused(false)}
        onKeyDown={onKeyDown}
      />
      {showSuggestions ? (
        <ul className="command-suggestions" aria-label="Command suggestions">
          <li>
            {/* Ask Heimlich is always first, even when an action matches (design spec §5.5). */}
            <button
              type="button"
              className="command-suggestion command-suggestion--ask"
              onMouseDown={(event) => {
                event.preventDefault();
                submit(value);
              }}
            >
              Ask Heimlich{trimmed ? ` using “${trimmed}”` : ""}
            </button>
          </li>
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
    </div>
  );
}
