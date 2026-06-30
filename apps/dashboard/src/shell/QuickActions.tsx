import { useActiveMode } from "./useActiveMode";
import { humanizeId } from "./labels";

/**
 * The binding 4 + 4 quick-action geometry (§5.7): four bars over four boxes, ALWAYS eight
 * slots, rendered from the active mode's `quickActions`. Actions are labelled but greyed and
 * disabled ("coming soon") until individually wired (course-correction E / NIC-58 / D4); a
 * null config slot renders as a disabled "Add action".
 */
function QuickActionSlot({ action, variant }: { action: string | null; variant: "bar" | "box" }) {
  return (
    <button
      type="button"
      className={`quick-action quick-action--${variant}`}
      disabled
      aria-disabled="true"
      title="Coming soon"
    >
      {action ? humanizeId(action) : "Add action"}
    </button>
  );
}

export function QuickActions() {
  const { quickActions } = useActiveMode();
  const bars = quickActions.slice(0, 4);
  const boxes = quickActions.slice(4, 8);

  return (
    <div className="quick-actions" role="group" aria-label="Quick actions">
      <div className="quick-actions__bars">
        {bars.map((action, index) => (
          <QuickActionSlot key={`bar-${index}`} action={action} variant="bar" />
        ))}
      </div>
      <div className="quick-actions__boxes">
        {boxes.map((action, index) => (
          <QuickActionSlot key={`box-${index}`} action={action} variant="box" />
        ))}
      </div>
    </div>
  );
}
