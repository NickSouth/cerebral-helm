import { render, screen, within, fireEvent, waitFor } from "@testing-library/react";
import { DashboardShell } from "../DashboardShell";
import { DashboardStateProvider } from "../../state/DashboardStateProvider";
import { BridgeProvider } from "../../state/BridgeProvider";
import { ConversationProvider } from "../../state/ConversationProvider";
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
              <ConversationProvider>
                <SettingsProvider>
                  <DashboardShell />
                </SettingsProvider>
              </ConversationProvider>
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

  it("lists all seven categories and pins an honest-disabled shutdown", () => {
    renderApp();
    const dialog = openSettings();
    for (const label of ["General", "Permissions", "Modes", "Actions", "Customization", "Setup", "Knowledge"]) {
      expect(within(dialog).getByRole("tab", { name: label })).toBeInTheDocument();
    }
    expect(within(dialog).getByRole("button", { name: /Shut down CerebralHelm/ })).toBeDisabled();
  });

  it("swaps the right pane when a category is selected", () => {
    renderApp();
    const dialog = openSettings();
    // General is the default — its Default mode control is present.
    expect(within(dialog).getByLabelText("Default mode")).toBeInTheDocument();

    fireEvent.click(within(dialog).getByRole("tab", { name: "Permissions" }));
    expect(within(dialog).queryByLabelText("Default mode")).toBeNull();
    // Permissions is read-only inspection: real tool ids + the deterministic-policy statement.
    expect(within(dialog).getByText("hook.run")).toBeInTheDocument();
    expect(within(dialog).getByText(/cannot be changed here/)).toBeInTheDocument();
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
    fireEvent.click(within(dialog).getByRole("tab", { name: "Customization" }));
    fireEvent.click(within(dialog).getByLabelText("Reduce motion"));

    // The override is applied at the themed root (synchronous, user-visible)...
    expect(document.querySelector(".app-root")?.getAttribute("data-reduced-motion")).toBe("true");
    // ...and the edit was accepted by the validation path (async).
    await waitFor(() => expect(accepted).toEqual([true]));
  });
});
