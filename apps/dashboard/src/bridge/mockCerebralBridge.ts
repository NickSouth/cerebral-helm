import type { DashboardBootstrapState } from "./types";

const bootstrapState: DashboardBootstrapState = {
  mode: "Developer",
  project: "NIC-12 Workspace Bootstrap",
  summary: "Pre-Mac foundation is running against a mock CerebralBridge.",
  commandsToday: 4,
  pendingConfirmations: 0,
  activeSurface: "Project Manager"
};

export function loadBootstrapState(): DashboardBootstrapState {
  return bootstrapState;
}
