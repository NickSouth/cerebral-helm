export type DashboardMode = "Executive" | "Developer" | "School" | "Entertainment";

export interface DashboardBootstrapState {
  readonly mode: DashboardMode;
  readonly project: string;
  readonly summary: string;
  readonly commandsToday: number;
  readonly pendingConfirmations: number;
  readonly activeSurface: string;
}
