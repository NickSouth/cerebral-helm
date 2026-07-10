import { fireEvent, render, screen } from "@testing-library/react";
import { SystemHealthPanel } from "./SystemHealthPanel";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { BridgeProvider } from "../state/BridgeProvider";
import { getDashboardConfigBundle, getDashboardFixture } from "../fixtures/canonicalFixtures";
import type { DashboardState, DashboardStore } from "../state/dashboardState";
import type { CerebralBridge, SpeedTestResult } from "../bridge/cerebralBridge";

/** A static store over a fixed state — no bridge, no subscriptions (the panel is pure render). */
function staticStore(state: DashboardState): DashboardStore {
  return { getState: () => state, subscribe: () => () => {} };
}

/** A bridge exposing only the speed-test call the Network row exercises. */
function stubBridge(runSpeedTest: () => Promise<SpeedTestResult>): CerebralBridge {
  return { runSpeedTest } as unknown as CerebralBridge;
}

function renderPanel(
  mutate: (base: DashboardState) => DashboardState,
  bridge: CerebralBridge = stubBridge(() => Promise.resolve({ status: "unavailable" }))
) {
  const base: DashboardState = {
    ...getDashboardConfigBundle(),
    ...getDashboardFixture("mode.executive.ready")
  };
  return render(
    <BridgeProvider bridge={bridge}>
      <DashboardStateProvider store={staticStore(mutate(base))}>
        <SystemHealthPanel />
      </DashboardStateProvider>
    </BridgeProvider>
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

  it("expands an inline speed-test panel from the wedge, then runs the test and shows up/down (NIC-135)", async () => {
    const bridge = stubBridge(() =>
      Promise.resolve({ status: "ok", downloadMbps: 243.7, uploadMbps: 17.9, testedAt: "2026-07-09T20:00:00.000Z" })
    );
    renderPanel(
      (base) => ({
        ...base,
        regions: {
          ...base.regions,
          systemHealth: {
            ...base.regions.systemHealth,
            state: "ready",
            network: { state: "ready", label: "Network", linkMbps: 866 }
          }
        }
      }),
      bridge
    );

    // Collapsed by default — no Test button until the wedge is opened.
    expect(screen.queryByRole("button", { name: "Test" })).toBeNull();

    fireEvent.click(screen.getByRole("button", { name: "Show speed test" }));
    fireEvent.click(screen.getByRole("button", { name: "Test" }));

    // The measured figures appear once the bridge resolves.
    expect(await screen.findByText("244")).toBeInTheDocument(); // 243.7 → 244 (≥100 rounds)
    expect(screen.getByText("17.9")).toBeInTheDocument();
    // And the button becomes a retest affordance.
    expect(screen.getByRole("button", { name: "Retest" })).toBeInTheDocument();
  });

  it("reports an honest 'unavailable' when the speed test cannot run (NIC-135)", async () => {
    renderPanel(
      (base) => ({
        ...base,
        regions: {
          ...base.regions,
          systemHealth: {
            ...base.regions.systemHealth,
            state: "ready",
            network: { state: "ready", label: "Network", linkMbps: 866 }
          }
        }
      }),
      stubBridge(() => Promise.resolve({ status: "unavailable" }))
    );

    fireEvent.click(screen.getByRole("button", { name: "Show speed test" }));
    fireEvent.click(screen.getByRole("button", { name: "Test" }));

    expect(await screen.findByText("Speed test unavailable")).toBeInTheDocument();
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
