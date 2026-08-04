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
interface ReportContextValue {
  readonly openReportId: string | null;
  openReport(reportId: string): void;
  closeReport(): void;
}

const ReportContext = createContext<ReportContextValue | null>(null);

export function ReportProvider({ children }: { children: ReactNode }) {
  const [openReportId, setOpenReportId] = useState<string | null>(null);
  const { mode } = useDashboardState();

  const openReport = useCallback((reportId: string) => {
    setOpenReportId((current) => (current === reportId ? null : reportId));
  }, []);
  const closeReport = useCallback(() => setOpenReportId(null), []);

  // A report is opened from a mode's slot and belongs to it: modes have different slot maps, so
  // School's `open-schedule` left hanging in Entertainment renders honestly ("Canvas is
  // unavailable") but reads as a bug. Switching mode closes it.
  useEffect(() => {
    setOpenReportId(null);
  }, [mode]);

  const value = useMemo(
    () => ({ openReportId, openReport, closeReport }),
    [openReportId, openReport, closeReport]
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
