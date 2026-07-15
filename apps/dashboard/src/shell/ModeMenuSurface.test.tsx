import { render, screen, within, fireEvent } from "@testing-library/react";
import { ModeMenuSurface } from "./ModeMenuSurface";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { BridgeProvider } from "../state/BridgeProvider";
import { AppearanceProvider } from "../state/AppearanceProvider";
import { ThemeProvider } from "../app/ThemeProvider";
import { createBridgeStore } from "../state/bridgeStore";
import { createMockCerebralBridge } from "../bridge/mockCerebralBridge";
import { getDashboardConfigBundle, getDashboardFixture } from "../fixtures/canonicalFixtures";

/**
 * The mode-swap dropdown surface (NIC-144): the content of the transparent, top-most
 * window that layers above open apps. Switches modes through the shared bridge and
 * dismisses itself via the native shellControl channel.
 */
function renderModeMenu() {
  const bridge = createMockCerebralBridge();
  const applyMode = vi.fn(bridge.applyMode.bind(bridge));
  bridge.applyMode = applyMode;
  const store = createBridgeStore(bridge, {
    ...getDashboardConfigBundle(),
    ...getDashboardFixture("mode.executive.ready")
  });
  const view = render(
    <BridgeProvider bridge={bridge}>
      <DashboardStateProvider store={store}>
        <AppearanceProvider>
          <ThemeProvider>
            <ModeMenuSurface />
          </ThemeProvider>
        </AppearanceProvider>
      </DashboardStateProvider>
    </BridgeProvider>
  );
  return { applyMode, ...view };
}

describe("ModeMenuSurface (?surface=modemenu)", () => {
  it("lists all modes with the active one checked", () => {
    renderModeMenu();
    const menu = screen.getByRole("menu", { name: "Switch mode" });
    const options = within(menu).getAllByRole("menuitemradio");
    expect(options.length).toBeGreaterThanOrEqual(4);
    // Executive is the active mode in this fixture.
    const executive = screen.getByRole("menuitemradio", { name: /Executive/ });
    expect(executive).toHaveAttribute("aria-checked", "true");
  });

  it("switches mode through the bridge and dismisses the window on select", () => {
    const posted: Array<Record<string, unknown>> = [];
    (window as unknown as { webkit?: unknown }).webkit = {
      messageHandlers: { shellControl: { postMessage: (m: unknown) => posted.push(m as Record<string, unknown>) } }
    };
    try {
      const { applyMode } = renderModeMenu();
      fireEvent.click(screen.getByRole("menuitemradio", { name: /Developer/ }));
      expect(applyMode).toHaveBeenCalledTimes(1);
      expect(applyMode.mock.calls[0][0]).toMatchObject({ modeId: expect.any(String) });
      expect(posted).toContainEqual(expect.objectContaining({ action: "closeModeMenu" }));
    } finally {
      delete (window as unknown as { webkit?: unknown }).webkit;
    }
  });

  it("does not re-apply the already-active mode, but still dismisses", () => {
    const posted: Array<Record<string, unknown>> = [];
    (window as unknown as { webkit?: unknown }).webkit = {
      messageHandlers: { shellControl: { postMessage: (m: unknown) => posted.push(m as Record<string, unknown>) } }
    };
    try {
      const { applyMode } = renderModeMenu();
      fireEvent.click(screen.getByRole("menuitemradio", { name: /Executive/ }));
      expect(applyMode).not.toHaveBeenCalled();
      expect(posted).toContainEqual(expect.objectContaining({ action: "closeModeMenu" }));
    } finally {
      delete (window as unknown as { webkit?: unknown }).webkit;
    }
  });

  it("Escape asks the shell to close the dropdown", () => {
    const posted: Array<Record<string, unknown>> = [];
    (window as unknown as { webkit?: unknown }).webkit = {
      messageHandlers: { shellControl: { postMessage: (m: unknown) => posted.push(m as Record<string, unknown>) } }
    };
    try {
      renderModeMenu();
      fireEvent.keyDown(document, { key: "Escape" });
      expect(posted).toContainEqual(expect.objectContaining({ action: "closeModeMenu" }));
    } finally {
      delete (window as unknown as { webkit?: unknown }).webkit;
    }
  });
});
