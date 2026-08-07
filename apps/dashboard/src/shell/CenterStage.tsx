import { useRef } from "react";
import { useTypewriter } from "./useTypewriter";
import { useEnterAfter, useLeaveTransition } from "./useLeaveTransition";
import { BeamOverlay } from "./BeamOverlay";
import { CenterShade } from "./CenterShade";
import { QuickApps } from "./QuickApps";
import { QuickActions } from "./QuickActions";
import { HeimlichConsciousness } from "./HeimlichConsciousness";
import { ReportRegion } from "../reports/ReportRegion";
import { InputRegion } from "../inputs/InputRegion";
import { useActiveMode } from "./useActiveMode";
import { useAppearance } from "../state/AppearanceProvider";
import { useReports } from "../state/ReportProvider";
import { useInputs } from "../state/InputProvider";

/**
 * The calm, dominant center (constitution §6): Quick Apps and the Heimlich consciousness
 * surface that always owns the center (course-correction A.1). The persistent command launcher
 * (C0, a global locus) sits in the shell's top row above this — a separate surface. This is the
 * `#main` skip-link target; the main product is immediately visible (NIC-53).
 *
 * A Report opens in the panel's left third and an Input in its lower right — they coexist by
 * design, since reading a brief while filling in an event is normal. The consciousness field
 * keeps running behind it — the report is opaque with a right-edge mask, so the stream dissolves
 * into it rather than being boxed away. The ambient greeting hides while a report is open, since
 * the report carries its own greeting block and the two would otherwise stack.
 */
export function CenterStage() {
  const { greeting, id: mode } = useActiveMode();
  const { assistantName, reducedMotion } = useAppearance();
  const { openReportId } = useReports();
  const { openInputId } = useInputs();
  const reportOpen = openReportId !== null;
  // The shade lives here rather than inside the report, so it can be a child of `.heimlich` and
  // reach the panel's edges. The ref is the seam between them: the report attaches it to its text,
  // the shade measures it.
  const reportContentRef = useRef<HTMLDivElement>(null);
  const inputContentRef = useRef<HTMLDivElement>(null);
  const inputOpen = openInputId !== null;
  const greetingRef = useRef<HTMLDivElement>(null);

  /**
   * The ambient greeting steps aside for EITHER surface, not just a report.
   *
   * It used to coexist with an input, which made the centre jump: the input sits above the
   * greeting in the foot, so opening a report afterwards removed the greeting and dropped the form
   * on top of the quick actions. Making the greeting exclusive with both removes the jump at its
   * source rather than pinning the form to the bar to hide it — and it is the rule the choreography
   * already followed everywhere else: the two surfaces coexist with each other, the greeting with
   * neither.
   *
   * Routed through the leave transition so it recedes rather than vanishing, at the same rate as
   * everything else in the centre.
   */
  const surfaceOpen = reportOpen || inputOpen;

  /**
   * The greeting is what leaves, so this tracks the greeting itself rather than "is a surface
   * open". Those are not the same question, and conflating them charged an exit's delay even when
   * the mode had no greeting to remove.
   *
   * Closing the last surface runs it in reverse for free: the greeting is wanted again, waits for
   * the surface to finish receding, and only then writes itself back in.
   */
  const greetingWanted = Boolean(greeting) && !surfaceOpen;
  const { shown: greetingVisible, leaving: greetingLeaving } = useLeaveTransition(greetingWanted);
  const showGreeting = greetingVisible;

  /**
   * The handover, owned here because this is the only place that can see both halves of it.
   *
   * Each surface knows its own state and nothing else, so left alone every one of them opened the
   * instant it was asked to — landing on top of a greeting that was still fading out. That read as
   * a stutter, which is exactly what it was: two animations running over each other with nothing
   * sequencing them.
   */
  const surfacesReady = useEnterAfter(greetingVisible);

  // Keyed on the mode, so entering a mode writes its greeting and nothing else retypes it.
  useTypewriter(greetingRef, showGreeting ? mode : null, { enabled: !reducedMotion });

  return (
    <main id="main" tabIndex={-1} className="shell-center">
      <QuickApps />

      <section
        className="heimlich"
        aria-label={assistantName}
        data-report-open={reportOpen || undefined}
      >
        <HeimlichConsciousness />
        <CenterShade side="report" open={reportOpen && surfacesReady} contentRef={reportContentRef} />
        <p className="heimlich__state">{assistantName}</p>
        <ReportRegion contentRef={reportContentRef} ready={surfacesReady} />
        <CenterShade side="input" open={inputOpen && surfacesReady} contentRef={inputContentRef} />
        <div className="heimlich__foot">
          <InputRegion contentRef={inputContentRef} ready={surfacesReady} />
          {greeting && showGreeting ? (
            /* Typed on every mode switch, the same way a report is. Today the line is hard-baked
               per mode; when a model writes it, only the source of the string changes — the
               choreography is already the shape a stream wants. */
            <div
              className="heimlich__greeting-block"
              ref={greetingRef}
              data-leaving={greetingLeaving || undefined}
            >
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
