import { render, screen, fireEvent } from "@testing-library/react";
import { describe, it, expect } from "vitest";
import { NewsPanel } from "./NewsPanel";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { BridgeProvider } from "../state/BridgeProvider";
import { ActionStatusProvider } from "../state/ActionStatusProvider";
import { createBridgeStore } from "../state/bridgeStore";
import { createMockCerebralBridge } from "../bridge/mockCerebralBridge";
import { getDashboardConfigBundle, getDashboardFixture } from "../fixtures/canonicalFixtures";
import type { DashboardState } from "../state/dashboardState";

/** Active mode is Executive → newsProfile "broad". Wraps the bridge/status/posture providers the
 *  clickable NewsPanel depends on, and records the raw commands the bridge receives. */
function renderPanel(mutate: (base: DashboardState) => DashboardState) {
  const bridge = createMockCerebralBridge();
  const submissions: string[] = [];
  const spyBridge = {
    ...bridge,
    submitCommand(input: { rawInput: string; source: string }) {
      submissions.push(input.rawInput);
      return bridge.submitCommand(input);
    }
  };
  const base: DashboardState = {
    ...getDashboardConfigBundle(),
    ...getDashboardFixture("mode.executive.ready")
  };
  const store = createBridgeStore(spyBridge, mutate(base));
  render(
    <BridgeProvider bridge={spyBridge}>
      <DashboardStateProvider store={store}>
        <ActionStatusProvider>
          <NewsPanel />
        </ActionStatusProvider>
      </DashboardStateProvider>
    </BridgeProvider>
  );
  return { submissions };
}

describe("NewsPanel", () => {
  it("resolves live per-profile headlines over the bootstrap region (NIC-127)", () => {
    renderPanel((base) => ({
      ...base,
      liveNews: {
        broad: {
          state: "ready",
          headlines: [
            { id: "n1", title: "Live broad headline one", source: "Reuters", url: "https://ex.com/1" },
            { id: "n2", title: "Live broad headline two", source: "Bloomberg", url: "https://ex.com/2" }
          ]
        }
      }
    }));
    expect(screen.getByText("Live broad headline one")).toBeInTheDocument();
    expect(screen.getByText("Live broad headline two")).toBeInTheDocument();
  });

  it("falls back to the bootstrap region when no live news for the active profile", () => {
    renderPanel((base) => ({
      ...base,
      regions: {
        ...base.regions,
        news: {
          state: "ready",
          headlines: [{ id: "b1", title: "Bootstrap headline", source: "Wire" }]
        }
      },
      // Live news exists, but only for a different profile — the active "broad" mode ignores it.
      liveNews: {
        engineering: {
          state: "ready",
          headlines: [{ id: "e1", title: "Engineering-only headline", source: "HN" }]
        }
      }
    }));
    expect(screen.getByText("Bootstrap headline")).toBeInTheDocument();
    expect(screen.queryByText("Engineering-only headline")).toBeNull();
  });

  it("opens a headline with a url in the browser via the web.open grammar (NIC-127)", () => {
    const { submissions } = renderPanel((base) => ({
      ...base,
      liveNews: {
        broad: {
          state: "ready",
          headlines: [
            { id: "n1", title: "Clickable story", source: "Reuters", url: "https://news.example.com/story" }
          ]
        }
      }
    }));
    fireEvent.click(screen.getByRole("button", { name: /Clickable story/ }));
    expect(submissions).toEqual(["web https://news.example.com/story"]);
  });

  it("renders a headline without a url as non-interactive text, never a dead button", () => {
    const { submissions } = renderPanel((base) => ({
      ...base,
      liveNews: {
        broad: {
          state: "ready",
          headlines: [{ id: "n1", title: "Linkless story", source: "Wire" }]
        }
      }
    }));
    expect(screen.getByText("Linkless story")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /Linkless story/ })).toBeNull();
    expect(submissions).toEqual([]);
  });

  it("disables the link and dispatches nothing while the dashboard is read-only", () => {
    const { submissions } = renderPanel((base) => ({
      ...base,
      recovery: { reason: "bridge_failure", startupMode: "recovery" },
      liveNews: {
        broad: {
          state: "ready",
          headlines: [
            { id: "n1", title: "Read-only story", source: "Reuters", url: "https://news.example.com/ro" }
          ]
        }
      }
    }));
    const button = screen.getByRole("button", { name: /Read-only story/ });
    expect(button).toBeDisabled();
    fireEvent.click(button);
    expect(submissions).toEqual([]);
  });
});
