export interface CommandSuggestion {
  readonly id: string;
  readonly label: string;
  readonly hint?: string;
  /** Capability-aware: false renders visibly unavailable, never fake-successful (NIC-58). */
  readonly available: boolean;
}

/**
 * The capability-aware command set the search surfaces suggest. Wired pre-Mac: note
 * capture/search and mode switch. Mac-only capabilities (app/url/hook) are shown but
 * disabled — visibly unavailable rather than fake-successful (NIC-58, FR-UI-07).
 */
export const COMMAND_SUGGESTIONS: readonly CommandSuggestion[] = [
  { id: "capture-note", label: "Capture a note", available: true },
  { id: "search-notes", label: "Search notes", available: true },
  { id: "switch-mode", label: "Switch mode", available: true },
  { id: "open-app", label: "Open an app", hint: "Available on the macOS host", available: false },
  { id: "run-command", label: "Run a system command", hint: "Available on the macOS host", available: false }
];

/** Suggestions whose label matches the query (case-insensitive); an empty query returns all. */
export function rankSuggestions(query: string): readonly CommandSuggestion[] {
  const normalized = query.trim().toLowerCase();
  if (!normalized) {
    return COMMAND_SUGGESTIONS;
  }
  return COMMAND_SUGGESTIONS.filter((suggestion) => suggestion.label.toLowerCase().includes(normalized));
}
