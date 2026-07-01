import { QuickApps } from "./QuickApps";
import { QuickActions } from "./QuickActions";
import { ConversationOverlay } from "./ConversationOverlay";
import { HeimlichRibbonEmbed } from "./HeimlichRibbonEmbed";
import { toRibbonState } from "./heimlichRibbon";
import { useDashboardState } from "../state/DashboardStateProvider";
import { useConversation } from "../state/ConversationProvider";
import { useActiveMode } from "./useActiveMode";

/**
 * The calm, dominant center (constitution §6): Quick Apps and the Heimlich consciousness
 * surface that always owns the center (course-correction A.1). The persistent Ask-Heimlich
 * launcher (C0, a global locus) sits in the shell's top row above this — a separate surface.
 * When a conversation is open it composites over the field as a translucent overlay with its
 * own docked input — never replacing the center. This is the `#main` skip-link target; the
 * main product is immediately visible (NIC-53).
 */
export function CenterStage() {
  const { heimlich } = useDashboardState();
  const { greeting } = useActiveMode();
  const conversation = useConversation();

  return (
    <main id="main" tabIndex={-1} className="shell-center">
      <QuickApps />

      <section className="heimlich" aria-label="Heimlich">
        <HeimlichRibbonEmbed state={toRibbonState(heimlich.state)} />
        <p className="heimlich__state">Heimlich</p>
        <div className="heimlich__foot">
          {greeting ? <p className="heimlich__greeting">{greeting.fallback}</p> : null}
          <QuickActions />
        </div>
        {conversation.open ? <ConversationOverlay /> : null}
      </section>
    </main>
  );
}
