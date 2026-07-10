import { act, render, screen, within, fireEvent, waitFor } from "@testing-library/react";
import { DashboardShell } from "../DashboardShell";
import { DashboardStateProvider } from "../../state/DashboardStateProvider";
import { BridgeProvider } from "../../state/BridgeProvider";
import { ActionStatusProvider } from "../../state/ActionStatusProvider";
import { SettingsProvider } from "../../state/SettingsProvider";
import { AppearanceProvider } from "../../state/AppearanceProvider";
import { ThemeProvider } from "../../app/ThemeProvider";
import { createBridgeStore } from "../../state/bridgeStore";
import { createMockCerebralBridge, loadBootstrapState } from "../../bridge/mockCerebralBridge";

/** Render the shell inside the full provider stack (mirrors AppRoot) so the settings window works. */
function renderApp() {
  const bridge = createMockCerebralBridge();
  const store = createBridgeStore(bridge, loadBootstrapState());
  return {
    bridge,
    ...render(
      <BridgeProvider bridge={bridge}>
        <DashboardStateProvider store={store}>
          <AppearanceProvider>
            <ThemeProvider>
              <ActionStatusProvider>
                <SettingsProvider>
                  <DashboardShell />
                </SettingsProvider>
              </ActionStatusProvider>
            </ThemeProvider>
          </AppearanceProvider>
        </DashboardStateProvider>
      </BridgeProvider>
    )
  };
}

function openSettings() {
  fireEvent.click(screen.getByRole("button", { name: "Settings" }));
  return screen.getByRole("dialog", { name: "Settings" });
}

describe("SettingsOverlay (E3 / NIC-63)", () => {
  it("opens from the bottom-bar gear and composites over the dashboard (does not replace it)", () => {
    renderApp();
    expect(screen.queryByRole("dialog", { name: "Settings" })).toBeNull();
    openSettings();
    // The dashboard is still mounted beneath the window (AC: settings does not replace dashboard).
    expect(screen.getByRole("region", { name: "Heimlich" })).toBeInTheDocument();
  });

  it("closes on Escape and via the close control", () => {
    renderApp();
    const dialog = openSettings();
    fireEvent.keyDown(dialog, { key: "Escape" });
    expect(screen.queryByRole("dialog", { name: "Settings" })).toBeNull();

    // Re-open, then close via the close control.
    const reopened = openSettings();
    fireEvent.click(within(reopened).getByRole("button", { name: "Close settings" }));
    expect(screen.queryByRole("dialog", { name: "Settings" })).toBeNull();
  });

  it("lists all six categories and pins an honest-disabled shutdown", () => {
    renderApp();
    const dialog = openSettings();
    for (const label of [
      "General",
      "Permissions",
      "Modes",
      "Actions",
      "Customization",
      "Setup"
    ]) {
      expect(within(dialog).getByRole("tab", { name: label })).toBeInTheDocument();
    }
    expect(within(dialog).getByRole("button", { name: /Shut down CerebralHelm/ })).toBeDisabled();
  });

  it("swaps the right pane when a category is selected", async () => {
    renderApp();
    const dialog = openSettings();
    // General is the default — its Reduce motion control seeds once the persisted read settles.
    expect(await within(dialog).findByLabelText("Reduce motion")).toBeInTheDocument();

    fireEvent.click(within(dialog).getByRole("tab", { name: "Permissions" }));
    expect(within(dialog).queryByLabelText("Reduce motion")).toBeNull();
    // Permissions is read-only inspection: real tool ids + the deterministic-policy statement.
    expect(within(dialog).getByText("hook.run")).toBeInTheDocument();
    expect(within(dialog).getByText(/cannot be changed here/)).toBeInTheDocument();
  });

  it("offers only stable-identity displays for Main display, defaulting to System primary (NIC-120b)", async () => {
    const { bridge } = renderApp();
    act(() => {
      bridge.emit({
        eventId: "brevt_displays0003",
        type: "display.topology.changed",
        schemaVersion: "1.0.0",
        timestamp: "2026-07-06T16:00:00.000Z",
        payload: {
          displays: [
            {
              id: "37D8832A-2D66-02CA-B9F7-8F30A301B230",
              name: "Built-in Display",
              frame: { x: 0, y: 0, width: 1512, height: 982 },
              primary: true,
              stableIdentity: true
            },
            {
              id: "cgid-724554883",
              name: "Unstable External",
              frame: { x: 1512, y: 0, width: 2560, height: 1440 },
              primary: false,
              stableIdentity: false
            }
          ],
          primaryDisplayId: "37D8832A-2D66-02CA-B9F7-8F30A301B230"
        }
      });
    });

    const dialog = openSettings();
    const select = await within(dialog).findByRole("combobox", { name: "Main display" });
    expect(select).toHaveValue("system-primary");
    const labels = within(select)
      .getAllByRole("option")
      .map((option) => option.textContent);
    // A session-scoped (non-stable) id must never be offered for persistence.
    expect(labels).toEqual(["System primary", "Built-in Display (primary)"]);
  });

  it("seeds the Modes controls from the persisted settings snapshot (NIC-141)", async () => {
    renderApp();
    const dialog = openSettings();
    fireEvent.click(within(dialog).getByRole("tab", { name: "Modes" }));
    // The mock returns a representative persisted state: developer + windows-stored-by-mode on.
    const modeSelect = await within(dialog).findByRole("combobox", { name: "Default mode" });
    expect(modeSelect).toHaveValue("developer");
    expect(within(dialog).getByLabelText("Windows Stored by Mode")).toBeChecked();
  });

  it("seeds the Knowledge root from the persisted settings snapshot (NIC-141)", async () => {
    renderApp();
    const dialog = openSettings();
    fireEvent.click(within(dialog).getByRole("tab", { name: "Setup" }));
    const input = await within(dialog).findByLabelText("Knowledge root reference");
    expect(input).toHaveValue("knowledge-root");
  });

  it("applies persisted reduced motion app-wide at startup, before settings is opened (NIC-141)", async () => {
    const bridge = createMockCerebralBridge();
    bridge.getSettings = () =>
      Promise.resolve({
        schemaVersion: "1.0.0",
        defaultModeId: "executive",
        appearance: { reducedMotion: true },
        knowledge: { rootReference: null },
        workspace: { windowsStoredByMode: false, mainDisplayId: "system-primary" }
      });
    const store = createBridgeStore(bridge, loadBootstrapState());
    render(
      <BridgeProvider bridge={bridge}>
        <DashboardStateProvider store={store}>
          <AppearanceProvider>
            <ThemeProvider>
              <ActionStatusProvider>
                <SettingsProvider>
                  <DashboardShell />
                </SettingsProvider>
              </ActionStatusProvider>
            </ThemeProvider>
          </AppearanceProvider>
        </DashboardStateProvider>
      </BridgeProvider>
    );
    // No settings interaction: the persisted preference reaches the themed root on its own.
    await waitFor(() =>
      expect(document.querySelector(".app-root")?.getAttribute("data-reduced-motion")).toBe("true")
    );
  });

  it("applies the Reduce motion toggle app-wide and submits an accepted patch", async () => {
    const { bridge } = renderApp();
    const accepted: boolean[] = [];
    const original = bridge.updateSettings.bind(bridge);
    bridge.updateSettings = async (input) => {
      const result = await original(input);
      accepted.push(result.accepted);
      return result;
    };

    const dialog = openSettings();
    // Reduce motion now lives in General (the default tab); it seeds once the read settles.
    fireEvent.click(await within(dialog).findByLabelText("Reduce motion"));

    // The override is applied at the themed root (synchronous, user-visible)...
    expect(document.querySelector(".app-root")?.getAttribute("data-reduced-motion")).toBe("true");
    // ...and the edit was accepted by the validation path (async).
    await waitFor(() => expect(accepted).toEqual([true]));
  });
});

describe("Settings surfaces under the native shell (backdrop-policy decision, 2026-07-06)", () => {
  interface ShellControlWindow {
    webkit?: { messageHandlers?: { shellControl?: { postMessage: (m: unknown) => void } } };
  }

  afterEach(() => {
    delete (window as unknown as ShellControlWindow).webkit;
  });

  it("the gear routes to the native settings window instead of the web overlay", () => {
    const postMessage = vi.fn();
    (window as unknown as ShellControlWindow).webkit = {
      messageHandlers: { shellControl: { postMessage } }
    };
    renderApp();
    fireEvent.click(screen.getByRole("button", { name: "Settings" }));
    // The dashboard is a strict backdrop: no in-page overlay when a native window exists.
    expect(postMessage).toHaveBeenCalledWith({ action: "openSettings" });
    expect(screen.queryByRole("dialog", { name: "Settings" })).toBeNull();
  });

  it("Launch at login reflects live OS status, toggles via shellControl, and explains approval (NIC-89)", async () => {
    const postMessage = vi.fn();
    (window as unknown as ShellControlWindow).webkit = {
      messageHandlers: { shellControl: { postMessage } }
    };
    interface LoginWindow {
      __cerebralLoginItem?: { status?: string };
      __cerebralLoginItemUpdate?: (status: string) => void;
    }
    (window as unknown as LoginWindow).__cerebralLoginItem = { status: "not-registered" };

    const { SettingsApp } = await import("../../app/SettingsApp");
    render(<SettingsApp />);
    const surface = screen.getByRole("main", { name: "Settings" });

    // The Launch-at-login control is in the General panel, which seeds from the
    // persisted read (NIC-141), so it mounts once that settles.
    const toggle = await within(surface).findByLabelText("Launch at login");
    expect(toggle).toBeEnabled();
    expect(toggle).not.toBeChecked();

    fireEvent.click(toggle);
    expect(postMessage).toHaveBeenCalledWith({ action: "setLoginItem", enabled: true });

    // The native shell pushes the OS's resulting status back — including the
    // requires-approval state, which the panel explains.
    act(() => {
      (window as unknown as LoginWindow).__cerebralLoginItemUpdate?.("requires-approval");
    });
    expect(within(surface).getByLabelText("Launch at login")).toBeChecked();
    expect(within(surface).getByText(/Waiting for approval/)).toBeInTheDocument();

    delete (window as unknown as LoginWindow).__cerebralLoginItem;
  });

  it("the standalone surface rebinds the palette shortcut and closes via the native channel", async () => {
    const postMessage = vi.fn();
    (window as unknown as ShellControlWindow).webkit = {
      messageHandlers: { shellControl: { postMessage } }
    };
    const { SettingsApp } = await import("../../app/SettingsApp");
    render(<SettingsApp />);
    const surface = screen.getByRole("main", { name: "Settings" });

    // The palette shortcut now lives in General (the default tab); it seeds once the read settles.
    const select = await within(surface).findByRole("combobox", {
      name: "Command palette shortcut"
    });
    fireEvent.change(select, { target: { value: "command-shift-space" } });
    expect(postMessage).toHaveBeenCalledWith({
      action: "setPaletteShortcut",
      preset: "command-shift-space"
    });

    fireEvent.click(within(surface).getByRole("button", { name: "Close settings" }));
    expect(postMessage).toHaveBeenCalledWith({ action: "closeSettings" });
  });
});
