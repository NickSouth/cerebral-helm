import { BeamOverlay } from "./BeamOverlay";
import { QuickApps } from "./QuickApps";
import { QuickActions } from "./QuickActions";
import { HeimlichConsciousness } from "./HeimlichConsciousness";
import { ReportRegion } from "../reports/ReportRegion";
import { InputRegion } from "../inputs/InputRegion";
import { useActiveMode } from "./useActiveMode";
import { useAppearance } from "../state/AppearanceProvider";
import { useReports } from "../state/ReportProvider";

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
  const { greeting } = useActiveMode();
  const { assistantName } = useAppearance();
  const { openReportId } = useReports();
  const reportOpen = openReportId !== null;

  return (
    <main id="main" tabIndex={-1} className="shell-center">
      <QuickApps />

      <section
        className="heimlich"
        aria-label={assistantName}
        data-report-open={reportOpen || undefined}
      >
        <HeimlichConsciousness />
        <p className="heimlich__state">{assistantName}</p>
        <ReportRegion />
        <div className="heimlich__foot">
          <InputRegion />
          {greeting && !reportOpen ? (
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
