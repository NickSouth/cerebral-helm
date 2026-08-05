import { useEffect, useId, useRef, useState, type KeyboardEvent } from "react";
import { BeamOverlay } from "./BeamOverlay";
import type { SuggestedCommand } from "../bridge/cerebralBridge";

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

const NO_SUGGESTIONS: readonly SuggestedCommand[] = [];
/** Keystroke-to-fetch debounce: long enough to coalesce bursts, short enough to feel live. */
const FETCH_DEBOUNCE_MS = 100;

/** Reference kinds carry a badge; templates show their grammar in the meta slot instead. */
const KIND_BADGES: Partial<Record<SuggestedCommand["kind"], string>> = {
  app: "app",
  url: "url",
  workflow: "action",
  mode: "mode",
  hook: "hook"
};

/** The next selectable (available) row from `from` in `delta` direction, or null. */
function nextAvailable(
  suggestions: readonly SuggestedCommand[],
  from: number | null,
  delta: 1 | -1
): number | null {
  const start = from ?? (delta === 1 ? -1 : suggestions.length);
  for (let index = start + delta; index >= 0 && index < suggestions.length; index += delta) {
    if (suggestions[index]?.available) {
      return index;
    }
  }
  return from;
}

/**
 * The shared command/search input. Used as the persistent top **launcher** (C0 — global, always
 * visible) on the dashboard and inside the floating command palette. Suggestions are ranked by
 * the bridge's `suggestCommands` (NIC-168) over the live catalogs — apps, URLs, workflows,
 * modes, hooks, grammar — typo-tolerant and capability-aware: unavailable actions render
 * visibly disabled, never fake-successful (NIC-58). Executing a suggestion submits its exact
 * `command` grammar string; template rows (`requiresArgument`) fill the input instead. Keyboard
 * grammar (design spec §5.5, Spotlight semantics — NIC-168): the best runnable row is selected
 * by default and its completion ghost-fills the input, so plain Enter executes the visibly
 * selected best guess; ↑/↓ move the selection over runnable rows; Tab (or → at the end of the
 * input) accepts the ghost completion without executing; Escape first clears the selection,
 * then closes. Enter with no selection still submits the typed text verbatim.
 */
export function CommandSurface({
  variant,
  placeholder,
  ariaLabel,
  onSubmit,
  fetchSuggestions,
  disabled = false,
  focusOnMount = false,
  spotlight = false
}: {
  variant: "launcher" | "docked";
  placeholder: string;
  ariaLabel: string;
  onSubmit: (text: string) => void;
  /**
   * Ranked suggestions for a query (NIC-168) — the bridge's `suggestCommands` behind a
   * function prop so the surface stays presentation-pure. Absent (or failing) suggestions
   * degrade to the bare input; typed submissions always keep working.
   */
  fetchSuggestions?: (query: string) => Promise<readonly SuggestedCommand[]>;
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
   * top launcher leaves this off and lists the supported grammar on focus.
   */
  spotlight?: boolean;
}) {
  const [value, setValue] = useState("");
  const [focused, setFocused] = useState(false);
  const [suggestions, setSuggestions] = useState<readonly SuggestedCommand[]>(NO_SUGGESTIONS);
  const [selectedIndex, setSelectedIndex] = useState<number | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  // Monotonic fetch sequence: only the latest request may apply its result, so a slow
  // early response can never repaint over a newer query (stale-response guard).
  const fetchSequence = useRef(0);
  const listId = useId();

  useEffect(() => {
    if (focusOnMount) {
      inputRef.current?.focus();
    }
  }, [focusOnMount]);

  const trimmed = value.trim();
  // The launcher fetches on focus (an empty query lists the supported grammar); in
  // spotlight mode the palette stays a bare bar until the user types (NIC-77).
  const wantSuggestions =
    focused && variant === "launcher" && !disabled && (!spotlight || trimmed.length > 0);

  useEffect(() => {
    if (!wantSuggestions || !fetchSuggestions) {
      fetchSequence.current += 1;
      setSuggestions(NO_SUGGESTIONS);
      setSelectedIndex(null);
      return;
    }
    const sequence = ++fetchSequence.current;
    const timer = setTimeout(() => {
      fetchSuggestions(trimmed).then(
        (rows) => {
          if (fetchSequence.current === sequence) {
            setSuggestions(rows);
            // Spotlight semantics: the best runnable row starts selected, so plain
            // Enter executes the visibly selected best guess (Escape clears it).
            setSelectedIndex(nextAvailable(rows, null, 1));
          }
        },
        () => {
          // A failed fetch degrades to the bare input — typing and submitting keep working.
          if (fetchSequence.current === sequence) {
            setSuggestions(NO_SUGGESTIONS);
            setSelectedIndex(null);
          }
        }
      );
    }, FETCH_DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [trimmed, wantSuggestions, fetchSuggestions]);

  function submit(text: string): void {
    if (disabled) {
      return;
    }
    const submittable = text.trim();
    if (!submittable) {
      return;
    }
    onSubmit(submittable);
    setValue("");
    setFocused(false);
  }

  /** Execute a runnable suggestion; a template still needing its argument fills the input. */
  function activate(suggestion: SuggestedCommand): void {
    if (!suggestion.available) {
      return;
    }
    if (suggestion.requiresArgument) {
      setValue(suggestion.command);
      setSelectedIndex(null);
      inputRef.current?.focus();
      return;
    }
    submit(suggestion.command);
  }

  const showSuggestions = wantSuggestions && suggestions.length > 0;
  const selected = selectedIndex === null ? undefined : suggestions[selectedIndex];

  // Inline ghost completion (NIC-168): when the selected row's command extends what
  // was typed, the remainder renders as ghost text after the caret — a visible
  // preview of exactly what Enter will run. Tab / → accept it without executing.
  const ghostSuffix =
    showSuggestions &&
    selected &&
    value.length > 0 &&
    selected.command.length > value.length &&
    selected.command.toLowerCase().startsWith(value.toLowerCase())
      ? selected.command.slice(value.length)
      : "";

  function acceptCompletion(): void {
    if (selected) {
      setValue(selected.command);
    }
  }

  function onKeyDown(event: KeyboardEvent<HTMLInputElement>): void {
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      if (!showSuggestions) {
        return;
      }
      event.preventDefault();
      setSelectedIndex(nextAvailable(suggestions, selectedIndex, event.key === "ArrowDown" ? 1 : -1));
    } else if (event.key === "Tab" && ghostSuffix) {
      event.preventDefault();
      acceptCompletion();
    } else if (event.key === "ArrowRight" && ghostSuffix) {
      // Only when the caret sits at the end — otherwise → keeps moving the caret.
      const input = event.currentTarget;
      if (input.selectionStart === value.length && input.selectionEnd === value.length) {
        event.preventDefault();
        acceptCompletion();
      }
    } else if (event.key === "Enter") {
      event.preventDefault();
      if (showSuggestions && selected) {
        activate(selected);
      } else {
        submit(value);
      }
    } else if (event.key === "Escape") {
      if (showSuggestions && selectedIndex !== null) {
        // Two-stage Escape: first clear the selection (and its ghost) — and stop
        // propagation so the palette's window-level Escape doesn't dismiss yet.
        event.stopPropagation();
        setSelectedIndex(null);
      } else {
        setFocused(false);
      }
    }
  }

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
        role="combobox"
        aria-expanded={showSuggestions}
        aria-controls={showSuggestions ? listId : undefined}
        aria-activedescendant={
          showSuggestions && selectedIndex !== null ? `${listId}-${selectedIndex}` : undefined
        }
        aria-autocomplete="both"
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
      {ghostSuffix ? (
        // Purely visual: the typed part is rendered invisibly so the suffix lands
        // exactly where the caret is; the input keeps all interaction.
        <span className="command-ghost" aria-hidden="true" data-testid="command-ghost">
          <span className="command-ghost__typed">{value}</span>
          {ghostSuffix}
        </span>
      ) : null}
      {showSuggestions ? (
        <ul className="command-suggestions" role="listbox" id={listId} aria-label="Command suggestions">
          {suggestions.map((suggestion, index) => {
            const isSelected = index === selectedIndex;
            const badge = KIND_BADGES[suggestion.kind];
            return (
              <li key={suggestion.command}>
                <button
                  type="button"
                  role="option"
                  id={`${listId}-${index}`}
                  aria-selected={isSelected}
                  className={
                    isSelected ? "command-suggestion command-suggestion--selected" : "command-suggestion"
                  }
                  disabled={!suggestion.available}
                  aria-disabled={!suggestion.available}
                  title={suggestion.unavailableReason ?? undefined}
                  onMouseDown={(event) => {
                    // preventDefault keeps focus in the input (a blur would close the list
                    // before the click lands).
                    event.preventDefault();
                    activate(suggestion);
                  }}
                >
                  <span className="command-suggestion__label">{suggestion.label}</span>
                  <span className="command-suggestion__meta">
                    <span className="command-suggestion__command">
                      {suggestion.detail ?? suggestion.command}
                    </span>
                    {badge ? <span className="command-suggestion__kind">{badge}</span> : null}
                    {suggestion.available ? null : (
                      <span className="command-suggestion__badge">unavailable</span>
                    )}
                  </span>
                </button>
              </li>
            );
          })}
        </ul>
      ) : null}
      {/* Only the launcher carries the beam ring (matching its outline styling). */}
      {variant === "launcher" ? <BeamOverlay /> : null}
    </div>
  );
}
