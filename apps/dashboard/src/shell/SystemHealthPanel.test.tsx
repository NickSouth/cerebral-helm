import { render, screen } from "@testing-library/react";
import { SystemHealthPanel } from "./SystemHealthPanel";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { getDashboardConfigBundle, getDashboardFixture } from "../fixtures/canonicalFixtures";
import type { DashboardState, DashboardStore } from "../state/dashboardState";

/** A static store over a fixed state — no bridge, no subscriptions (the panel is pure render). */
function staticStore(state: DashboardState): DashboardStore {
  return { getState: () => state, subscribe: () => () => {} };
}

function renderPanel(mutate: (base: DashboardState) => DashboardState) {
  const base: DashboardState = {
    ...getDashboardConfigBundle(),
    ...getDashboardFixture("mode.executive.ready")
  };
  return render(
    <DashboardStateProvider store={staticStore(mutate(base))}>
      <SystemHealthPanel />
    </DashboardStateProvider>
  );
}

describe("SystemHealthPanel", () => {
  it("renders live metrics when the region is ready", () => {
    renderPanel((base) => base);
    expect(screen.getByText("CPU")).toBeInTheDocument();
    expect(screen.queryByText("Metrics unavailable")).toBeNull();
    expect(screen.queryByText(/Loading system metrics/)).toBeNull();
  });

  it("renders the Wi-Fi link speed as a single Mbps figure, not an up/down split (NIC-135)", () => {
    renderPanel((base) => ({
      ...base,
      regions: {
        ...base.regions,
        systemHealth: {
          ...base.regions.systemHealth,
          state: "ready",
          network: { state: "ready", label: "Network", linkMbps: 866 }
        }
      }
    }));

    expect(screen.getByText("866 Mbps")).toBeInTheDocument();
    // No directional arrows any more — link speed is one number.
    expect(screen.queryByText("↑")).toBeNull();
    expect(screen.queryByText("↓")).toBeNull();
  });

  it("shows an honest 'No Wi-Fi' when there is no link rate (Ethernet / Wi-Fi off) (NIC-135)", () => {
    renderPanel((base) => ({
      ...base,
      regions: {
        ...base.regions,
        systemHealth: {
          ...base.regions.systemHealth,
          state: "ready",
          network: { state: "unavailable", label: "Network" }
        }
      }
    }));

    expect(screen.getByText("No Wi-Fi")).toBeInTheDocument();
  });

  it("shows a same-shape skeleton while a sample is expected, not the unavailable flash (NIC-136)", () => {
    const { container } = renderPanel((base) => ({
      ...base,
      capabilities: { "system.metrics": { available: true, degradedReason: null } },
      regions: {
        ...base.regions,
        systemHealth: {
          state: "unavailable",
          battery: { state: "unavailable", label: "Battery" }
        }
      }
    }));

    // The loading state announces itself and keeps the row shape (icon + label present)…
    expect(screen.getByText(/Loading system metrics/)).toBeInTheDocument();
    expect(screen.getByText("CPU")).toBeInTheDocument();
    expect(screen.getByText("Battery")).toBeInTheDocument();
    expect(container.querySelectorAll(".skeleton-bone").length).toBeGreaterThan(0);
    // …and never flashes the honest-unavailable copy.
    expect(screen.queryByText("Metrics unavailable")).toBeNull();
  });

  it("renders honest-unavailable when no metrics provider is expected", () => {
    const { container } = renderPanel((base) => ({
      ...base,
      capabilities: {},
      regions: {
        ...base.regions,
        systemHealth: {
          state: "unavailable",
          battery: { state: "unavailable", label: "Battery" }
        }
      }
    }));

    expect(screen.getByText("Metrics unavailable")).toBeInTheDocument();
    expect(screen.queryByText(/Loading system metrics/)).toBeNull();
    expect(container.querySelectorAll(".skeleton-bone").length).toBe(0);
  });
});
