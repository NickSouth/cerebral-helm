import { useEffect, useRef } from "react";

/**
 * The search field every app-list surface wears (NIC-167): More Apps, the quick-app pin popover,
 * the layout hot-swap picker, and the layout editor's picker.
 *
 * Shared rather than repeated so the four surfaces cannot drift in placeholder, focus behaviour, or
 * clear affordance — a user who learns to type in one has learned all four.
 *
 * Autofocused: these surfaces are summoned to find one specific app, so the keyboard should already
 * be in the right place. `type="search"` gets the platform clear control for free; Escape is
 * deliberately **not** handled here — it belongs to the dialog, and swallowing it would break the
 * established "Escape closes the picker" behaviour when the field happens to hold focus.
 */
export function PickerSearchField({
  value,
  onChange,
  label,
  placeholder = "Search apps…",
  className = "pin-pop__field pin-pop__field--search"
}: {
  value: string;
  onChange: (value: string) => void;
  label: string;
  placeholder?: string;
  className?: string;
}) {
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  return (
    <input
      ref={inputRef}
      type="search"
      className={className}
      aria-label={label}
      placeholder={placeholder}
      value={value}
      onChange={(event) => onChange(event.target.value)}
    />
  );
}

export default PickerSearchField;
