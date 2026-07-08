import { BeamOverlay } from "./BeamOverlay";
import { QuickApps } from "./QuickApps";
import { QuickActions } from "./QuickActions";
import { HeimlichConsciousness } from "./HeimlichConsciousness";
import { useActiveMode } from "./useActiveMode";

/**
 * The calm, dominant center (constitution §6): Quick Apps and the Heimlich consciousness
 * surface that always owns the center (course-correction A.1). The persistent command launcher
 * (C0, a global locus) sits in the shell's top row above this — a separate surface. The Heimlich
 * conversation was removed (NIC-124): conversing with Heimlich is post-MVP and there is no agent
 * to talk to, so nothing composites over the field here. This is the `#main` skip-link target;
 * the main product is immediately visible (NIC-53).
 */
export function CenterStage() {
  const { greeting } = useActiveMode();

  return (
    <main id="main" tabIndex={-1} className="shell-center">
      <QuickApps />

      <section className="heimlich" aria-label="Heimlich">
        <HeimlichConsciousness />
        <p className="heimlich__state">Heimlich</p>
        <div className="heimlich__foot">
          {greeting ? (
            <div className="heimlich__greeting-block">
              <p className="heimlich__greeting">{greeting.fallback}</p>
              {greeting.subtitle ? (
                <p className="heimlich__subgreeting">{greeting.subtitle}</p>
              ) : null}
            </div>
          ) : null}
          <QuickActions />
        </div>
        <BeamOverlay />
      </section>
    </main>
  );
}
