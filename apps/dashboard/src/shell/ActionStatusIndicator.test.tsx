import { act, render, screen } from "@testing-library/react";
import { ActionStatusIndicator } from "./ActionStatusIndicator";
import { ActionStatusProvider, useActionStatus } from "../state/ActionStatusProvider";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { createBridgeStore } from "../state/bridgeStore";
import { createMockCerebralBridge } from "../bridge/mockCerebralBridge";
import { getDashboardConfigBundle, getDashboardFixture } from "../fixtures/canonicalFixtures";

/** A test-only trigger that exposes `announce` as a pair of buttons. */
function AnnounceProbe() {
  const { announce } = useActionStatus();
  return (
    <>
      <button type="button" onClick={() => announce("Captured a quick note (n1).")}>
        info
      </button>
      <button type="button" onClick={() => announce("Opening Xcode failed.", "error")}>
        error
      </button>
    </>
  );
}

function renderIndicator() {
  const bridge = createMockCerebralBridge();
  const store = createBridgeStore(bridge, {
    ...getDashboardConfigBundle(),
    ...getDashboardFixture("mode.executive.ready")
  });
  return render(
    <DashboardStateProvider store={store}>
      <ActionStatusProvider>
        <AnnounceProbe />
        <ActionStatusIndicator />
      </ActionStatusProvider>
    </DashboardStateProvider>
  );
}

describe("ActionStatusIndicator (NIC-124)", () => {
  it("is idle-empty until something is announced", () => {
    renderIndicator();
    const region = document.querySelector(".action-status") as HTMLElement;
    expect(region).not.toBeNull();
    expect(region).toHaveTextContent("");
    expect(region).not.toHaveAttribute("data-severity");
  });

  it("shows an info announcement as quiet text with no error icon", () => {
    renderIndicator();
    act(() => {
      screen.getByRole("button", { name: "info" }).click();
    });
    const region = document.querySelector(".action-status") as HTMLElement;
    expect(region).toHaveTextContent("Captured a quick note (n1).");
    expect(region).toHaveAttribute("data-severity", "info");
    expect(region.querySelector(".action-status__icon")).toBeNull();
  });

  it("shows an error announcement in the error tint with an X icon", () => {
    renderIndicator();
    act(() => {
      screen.getByRole("button", { name: "error" }).click();
    });
    const region = document.querySelector(".action-status") as HTMLElement;
    expect(region).toHaveTextContent("Opening Xcode failed.");
    expect(region).toHaveAttribute("data-severity", "error");
    expect(region.querySelector(".action-status__icon")).not.toBeNull();
  });

  it("auto-dismisses a transient announcement", () => {
    vi.useFakeTimers();
    try {
      renderIndicator();
      act(() => {
        screen.getByRole("button", { name: "info" }).click();
      });
      expect(document.querySelector(".action-status")).toHaveTextContent("Captured a quick note");
      act(() => {
        vi.advanceTimersByTime(6000);
      });
      expect(document.querySelector(".action-status")).toHaveTextContent("");
    } finally {
      vi.useRealTimers();
    }
  });
});
