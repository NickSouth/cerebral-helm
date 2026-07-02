interface UnavailableProps {
  /** What is unavailable. Defaults to a generic honest-unavailable label. */
  label?: string;
}

/**
 * The honest-unavailable primitive: an unwired capability shown as visibly disabled,
 * never fake-successful (FR-UI-07). Carries accessible text, not color alone.
 */
export function Unavailable({ label = "Not implemented" }: UnavailableProps) {
  return (
    <span className="unavailable" aria-disabled="true">
      {label}
    </span>
  );
}

export default Unavailable;
