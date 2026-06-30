import { QuickApps } from "./QuickApps";
import { QuickActions } from "./QuickActions";
import { CommandSurface } from "./CommandSurface";
import { ConversationOverlay } from "./ConversationOverlay";
import { useDashboardState } from "../state/DashboardStateProvider";
import { useConversation } from "../state/ConversationProvider";
import { useActiveMode } from "./useActiveMode";
import { heimlichStateLabel } from "./labels";

/**
 * The calm, dominant center (constitution §6): the persistent Ask-Heimlich launcher (C0, a
 * global locus), Quick Apps, and the Heimlich consciousness surface that always owns the
 * center (course-correction A.1). When a conversation is open it composites over the field as
 * a translucent overlay with its own docked input — never replacing the center. This is the
 * `#main` skip-link target; the main product is immediately visible (NIC-53).
 */
export function CenterStage() {
  const { heimlich } = useDashboardState();
  const { greeting } = useActiveMode();
  const conversation = useConversation();

  return (
    <main id="main" tabIndex={-1} className="shell-center">
      <CommandSurface
        variant="launcher"
        placeholder="Ask Heimlich or type a command…"
        ariaLabel="Ask Heimlich or type a command"
        onSubmit={conversation.submit}
      />

      <QuickApps />

      <section className="heimlich" aria-label="Heimlich">
        <div className="heimlich__ambient">
          <p className="eyebrow">Heimlich · {heimlichStateLabel(heimlich.state)}</p>
          {greeting ? <p className="heimlich__greeting">{greeting.fallback}</p> : null}
        </div>
        <QuickActions />
        {conversation.open ? <ConversationOverlay /> : null}
      </section>
    </main>
  );
}
