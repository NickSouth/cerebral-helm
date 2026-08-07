import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode
} from "react";
import { useDashboardState } from "./DashboardStateProvider";

/**
 * Which Report is open in the centre panel, if any.
 *
 * One at a time, by design: the region occupies a fixed share of the centre panel, so a second
 * report replaces the first rather than stacking. Opening is idempotent, and opening the report
 * that is already open closes it — the quick-action slot doubles as its own toggle, which is what
 * a user pressing "Daily brief" twice expects.
 */
/**
 * Arguments a report was opened with.
 *
 * Reports began parameterless — every composer read ambient dashboard state, so the id was the
 * whole request. `check-scoreboard` broke that: it is a Report chosen *from* an Input, and which
 * games it shows is the user's answer, not something in ambient state. Kept as a plain string
 * array because that is what the one case needs; widen it when a second case actually asks.
 */
export type ReportParams = readonly string[];

interface ReportContextValue {
  readonly openReportId: string | null;
  /** The arguments the open report was opened with; empty for a parameterless report. */
  readonly openReportParams: ReportParams;
  openReport(reportId: string, params?: ReportParams): void;
  closeReport(): void;
}

const ReportContext = createContext<ReportContextValue | null>(null);

/**
 * `handoff` lets a host open reports somewhere other than itself. The edge sidebar uses it: a
 * report is a reading surface sized for the centre panel, so opening one from the column reveals
 * the dashboard and renders it there instead of cramming a second copy into 340px (owner decision,
 * 2026-08-03). Returning true means "handled elsewhere" and suppresses the local open; returning
 * false falls through to normal behavior.
 */
export function ReportProvider({
  children,
  handoff
}: {
  children: ReactNode;
  handoff?: (reportId: string) => boolean;
}) {
  const [openReportId, setOpenReportId] = useState<string | null>(null);
  const [openReportParams, setOpenReportParams] = useState<ReportParams>([]);
  const { mode } = useDashboardState();

  const openReport = useCallback(
    (reportId: string, params: ReportParams = []) => {
      if (handoff?.(reportId)) {
        return;
      }
      setOpenReportId((current) => {
        // Re-opening the same report with NEW arguments is a fresh request, not a toggle: picking
        // a different set of games and pressing Create should show them, not close the panel.
        const reopeningWithNewParams = current === reportId && params.length > 0;
        return current === reportId && !reopeningWithNewParams ? null : reportId;
      });
      setOpenReportParams(params);
    },
    [handoff]
  );
  const closeReport = useCallback(() => {
    setOpenReportId(null);
    setOpenReportParams([]);
  }, []);

  // A report is opened from a mode's slot and belongs to it: modes have different slot maps, so
  // School's `open-schedule` left hanging in Entertainment renders honestly ("Canvas is
  // unavailable") but reads as a bug. Switching mode closes it.
  useEffect(() => {
    setOpenReportId(null);
    setOpenReportParams([]);
  }, [mode]);

  const value = useMemo(
    () => ({ openReportId, openReportParams, openReport, closeReport }),
    [openReportId, openReportParams, openReport, closeReport]
  );

  return <ReportContext.Provider value={value}>{children}</ReportContext.Provider>;
}

export function useReports(): ReportContextValue {
  const value = useContext(ReportContext);
  if (!value) {
    throw new Error("useReports must be used within a ReportProvider.");
  }
  return value;
}
