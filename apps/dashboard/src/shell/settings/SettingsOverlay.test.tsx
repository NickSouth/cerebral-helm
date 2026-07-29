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
    // Permissions inspection: real tool ids + the deterministic-policy statement (it seeds
    // the tightening toggle from the persisted read, so the list settles asynchronously).
    expect(await within(dialog).findByText("hook.run")).toBeInTheDocument();
    expect(within(dialog).getByText(/cannot be relaxed here/)).toBeInTheDocument();
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

  it("captures and saves a mode layout in the Modes panel (NIC-142)", async () => {
    renderApp();
    const dialog = openSettings();
    fireEvent.click(within(dialog).getByRole("tab", { name: "Modes" }));

    // Open the first non-Executive mode's layout editor. There is no native channel in
    // jsdom, so "Edit layout" falls back to the inline editor (NIC-142 increment 4).
    const editButtons = await within(dialog).findAllByRole("button", { name: /^Edit .+ layout$/ });
    fireEvent.click(editButtons[0]);

    // Capture the mode's currently-arranged windows (seeds the canvas + hotswap slot).
    const capture = await within(dialog).findByRole("button", { name: "Capture current windows" });
    fireEvent.click(capture);
    const save = await within(dialog).findByRole("button", { name: "Save layout" });

    // Add a second hotswap target via the Quick Apps-style picker (NIC-142 increment 6).
    fireEvent.click(await within(dialog).findByRole("button", { name: "Add hotswap target" }));
    const picker = await within(dialog).findByRole("dialog", { name: "Add a hotswap target" });
    fireEvent.click(await within(picker).findByRole("button", { name: "Add Terminal" }));
    // The target becomes a removable chip in the hotswap list.
    await within(dialog).findByRole("button", { name: "Remove hotswap Terminal" });
    fireEvent.click(within(picker).getByRole("button", { name: "Close pin menu" }));

    fireEvent.click(save);
    await within(dialog).findByText("Layout saved.");
  });

  it("seeds the Knowledge root from the persisted settings snapshot (NIC-141)", async () => {
    renderApp();
    const dialog = openSettings();
    fireEvent.click(within(dialog).getByRole("tab", { name: "Setup" }));
    const input = await within(dialog).findByLabelText("Knowledge root reference");
    expect(input).toHaveValue("knowledge-root");
  });

  it("honest-disables the knowledge-root Browse button without a native shell (NIC-138)", async () => {
    renderApp();
    const dialog = openSettings();
    fireEvent.click(within(dialog).getByRole("tab", { name: "Setup" }));
    expect(await within(dialog).findByRole("button", { name: "Browse…" })).toBeDisabled();
  });

  it("stores the TMDB API key through the bridge and reflects it as set, never echoing the value (NIC-134)", async () => {
    const { bridge } = renderApp();
    const stored: Array<{ reference: string; value: string }> = [];
    const realStore = bridge.storeSecret.bind(bridge);
    bridge.storeSecret = (input) => {
      stored.push({ reference: input.reference, value: input.value });
      return realStore(input);
    };

    const dialog = openSettings();
    fireEvent.click(within(dialog).getByRole("tab", { name: "Setup" }));

    // Scope to the TMDB field — the section also has a Finnhub key field and its own Save buttons.
    const input = await within(dialog).findByLabelText("TMDB API key");
    const field = input.closest(".settings-field") as HTMLElement;
    // Presence read settles to "Not set" (no key seeded in the mock).
    expect(await within(field).findByText("Not set")).toBeInTheDocument();
    fireEvent.change(input, { target: { value: "tmdb-secret-xyz" } });
    fireEvent.click(within(field).getByRole("button", { name: "Save" }));

    // The key reached the bridge with the correct logical reference.
    await waitFor(() => expect(stored).toHaveLength(1));
    expect(stored[0]).toEqual({ reference: "tmdb_api_key", value: "tmdb-secret-xyz" });

    // The field now reports "Key set" and no longer holds the value (never echoed back).
    expect(await within(field).findByText("Key set")).toBeInTheDocument();
    expect(input).toHaveValue("");
  });

  it("stores the Finnhub API key under its own reference, alongside the TMDB field (NIC-128)", async () => {
    const { bridge } = renderApp();
    const stored: Array<{ reference: string; value: string }> = [];
    const realStore = bridge.storeSecret.bind(bridge);
    bridge.storeSecret = (input) => {
      stored.push({ reference: input.reference, value: input.value });
      return realStore(input);
    };

    const dialog = openSettings();
    fireEvent.click(within(dialog).getByRole("tab", { name: "Setup" }));

    const input = await within(dialog).findByLabelText("Finnhub API key");
    const field = input.closest(".settings-field") as HTMLElement;
    expect(await within(field).findByText("Not set")).toBeInTheDocument();
    fireEvent.change(input, { target: { value: "finnhub-secret-abc" } });
    fireEvent.click(within(field).getByRole("button", { name: "Save" }));

    await waitFor(() => expect(stored).toHaveLength(1));
    expect(stored[0]).toEqual({ reference: "finnhub_api_key", value: "finnhub-secret-abc" });
    expect(await within(field).findByText("Key set")).toBeInTheDocument();
    expect(input).toHaveValue("");
  });

  it("stores the NewsData API key under its own reference (NIC-127)", async () => {
    const { bridge } = renderApp();
    const stored: Array<{ reference: string; value: string }> = [];
    const realStore = bridge.storeSecret.bind(bridge);
    bridge.storeSecret = (input) => {
      stored.push({ reference: input.reference, value: input.value });
      return realStore(input);
    };

    const dialog = openSettings();
    fireEvent.click(within(dialog).getByRole("tab", { name: "Setup" }));

    const input = await within(dialog).findByLabelText("NewsData API key");
    const field = input.closest(".settings-field") as HTMLElement;
    expect(await within(field).findByText("Not set")).toBeInTheDocument();
    fireEvent.change(input, { target: { value: "newsdata-secret-123" } });
    fireEvent.click(within(field).getByRole("button", { name: "Save" }));

    await waitFor(() => expect(stored).toHaveLength(1));
    expect(stored[0]).toEqual({ reference: "newsdata_api_key", value: "newsdata-secret-123" });
    expect(await within(field).findByText("Key set")).toBeInTheDocument();
    // The value is never echoed back into the field.
    expect(input).toHaveValue("");
  });

  it("stores the GitHub personal access token under its own reference (NIC-130)", async () => {
    const { bridge } = renderApp();
    const stored: Array<{ reference: string; value: string }> = [];
    const realStore = bridge.storeSecret.bind(bridge);
    bridge.storeSecret = (input) => {
      stored.push({ reference: input.reference, value: input.value });
      return realStore(input);
    };

    const dialog = openSettings();
    fireEvent.click(within(dialog).getByRole("tab", { name: "Setup" }));

    const input = await within(dialog).findByLabelText("GitHub personal access token");
    const field = input.closest(".settings-field") as HTMLElement;
    expect(await within(field).findByText("Not set")).toBeInTheDocument();
    fireEvent.change(input, { target: { value: "ghp_secret_token" } });
    fireEvent.click(within(field).getByRole("button", { name: "Save" }));

    await waitFor(() => expect(stored).toHaveLength(1));
    expect(stored[0]).toEqual({ reference: "github_api_token", value: "ghp_secret_token" });
    expect(await within(field).findByText("Key set")).toBeInTheDocument();
    // The token is never echoed back into the field.
    expect(input).toHaveValue("");
  });

  it("stores the Spotify Client ID under its own reference (NIC-133)", async () => {
    const { bridge } = renderApp();
    const stored: Array<{ reference: string; value: string }> = [];
    const realStore = bridge.storeSecret.bind(bridge);
    bridge.storeSecret = (input) => {
      stored.push({ reference: input.reference, value: input.value });
      return realStore(input);
    };

    const dialog = openSettings();
    fireEvent.click(within(dialog).getByRole("tab", { name: "Setup" }));

    const input = await within(dialog).findByLabelText("Spotify Client ID");
    const field = input.closest(".settings-field") as HTMLElement;
    expect(await within(field).findByText("Not set")).toBeInTheDocument();
    fireEvent.change(input, { target: { value: "spotify-client-abc" } });
    fireEvent.click(within(field).getByRole("button", { name: "Save" }));

    await waitFor(() => expect(stored).toHaveLength(1));
    expect(stored[0]).toEqual({ reference: "spotify_client_id", value: "spotify-client-abc" });
    expect(await within(field).findByText("Key set")).toBeInTheDocument();
    expect(input).toHaveValue("");
  });

  it("connects Spotify via the OAuth op and disconnects by clearing the token (NIC-133)", async () => {
    const { bridge } = renderApp();
    const connectCalls: number[] = [];
    const deleted: string[] = [];
    const realConnect = bridge.connectSpotify.bind(bridge);
    bridge.connectSpotify = () => {
      connectCalls.push(1);
      return realConnect();
    };
    const realDelete = bridge.deleteSecret.bind(bridge);
    bridge.deleteSecret = (input) => {
      deleted.push(input.reference);
      return realDelete(input);
    };

    const dialog = openSettings();
    fireEvent.click(within(dialog).getByRole("tab", { name: "Setup" }));

    // The connect control lives in the "Spotify account" field, distinct from the Client ID key field.
    const field = (await within(dialog).findByText("Spotify account")).closest(
      ".settings-field"
    ) as HTMLElement;
    expect(await within(field).findByText("Not connected")).toBeInTheDocument();

    fireEvent.click(within(field).getByRole("button", { name: "Connect Spotify" }));
    await waitFor(() => expect(connectCalls).toHaveLength(1));
    // The mock binds spotify_oauth, so the control flips to Connected and offers Disconnect.
    expect(await within(field).findByText("Connected")).toBeInTheDocument();

    fireEvent.click(within(field).getByRole("button", { name: "Disconnect" }));
    await waitFor(() => expect(deleted).toEqual(["spotify_oauth"]));
    expect(await within(field).findByText("Not connected")).toBeInTheDocument();
  });

  it("disables Save until a key is entered (NIC-134)", async () => {
    renderApp();
    const dialog = openSettings();
    fireEvent.click(within(dialog).getByRole("tab", { name: "Setup" }));
    const field = (await within(dialog).findByLabelText("TMDB API key")).closest(
      ".settings-field"
    ) as HTMLElement;
    await within(field).findByText("Not set");
    expect(within(field).getByRole("button", { name: "Save" })).toBeDisabled();
  });

  it("edits the tracked stock tickers and saves the list through the settings path (NIC-128)", async () => {
    const { bridge } = renderApp();
    const patches: Array<Record<string, unknown>> = [];
    const realUpdate = bridge.updateSettings.bind(bridge);
    bridge.updateSettings = (input) => {
      patches.push(input.patch.changes as Record<string, unknown>);
      return realUpdate(input);
    };

    const dialog = openSettings();
    fireEvent.click(within(dialog).getByRole("tab", { name: "Setup" }));

    // The editor seeds from the persisted snapshot's starter list.
    const addInput = await within(dialog).findByLabelText("Add a stock ticker");
    const field = addInput.closest(".settings-field") as HTMLElement;
    expect(within(field).getByText("SPY")).toBeInTheDocument();

    // A lowercase symbol is uppercased into a chip on Add.
    fireEvent.change(addInput, { target: { value: "tsla" } });
    fireEvent.click(within(field).getByRole("button", { name: "Add" }));
    expect(within(field).getByText("TSLA")).toBeInTheDocument();

    // Remove one of the starters.
    fireEvent.click(within(field).getByRole("button", { name: "Remove AAPL" }));
    expect(within(field).queryByText("AAPL")).toBeNull();

    // Save persists the edited list through updateSettings.
    fireEvent.click(within(field).getByRole("button", { name: "Save" }));
    await waitFor(() => expect(patches).toHaveLength(1));
    expect(patches[0]).toEqual({ stocks: { tickers: ["SPY", "NVDA", "VTI", "TSLA"] } });
  });

  it("maps a calendar to a mode and saves it through the settings path (NIC-126)", async () => {
    const { bridge } = renderApp();
    const patches: Array<Record<string, unknown>> = [];
    const realUpdate = bridge.updateSettings.bind(bridge);
    bridge.updateSettings = (input) => {
      patches.push(input.patch.changes as Record<string, unknown>);
      return realUpdate(input);
    };

    const dialog = openSettings();
    fireEvent.click(within(dialog).getByRole("tab", { name: "Setup" }));

    // The mapping field lists the host's calendars (mock: Work / Personal / School / Family).
    const workSelect = await within(dialog).findByLabelText("Mode for Work");
    fireEvent.change(workSelect, { target: { value: "developer" } });

    // The change writes the whole calendar→mode map through the settings path.
    await waitFor(() => expect(patches).toHaveLength(1));
    expect(patches[0]).toEqual({ calendarModeMap: { "cal-work": "developer" } });
  });

  it("shows the Canvas pairing token + last-scrape status and disconnects (NIC-132)", async () => {
    renderApp();
    const dialog = openSettings();
    fireEvent.click(within(dialog).getByRole("tab", { name: "Setup" }));

    // Scope to the Canvas card by its label so its Disconnect doesn't clash with other cards.
    const label = await within(dialog).findByText("Canvas (School widgets)");
    const canvas = within(label.closest(".settings-field") as HTMLElement);

    // The pairing token and the last-scrape summary are shown (mock: 4 courses, 7 deadlines).
    expect(await canvas.findByText("mock-canvas-token")).toBeInTheDocument();
    expect(canvas.getByText(/4 courses, 7 deadlines/)).toBeInTheDocument();

    // Disconnect rotates the token and clears the scrape summary (purge + rotate).
    fireEvent.click(canvas.getByRole("button", { name: "Disconnect" }));
    expect(await canvas.findByText("mock-canvas-token-rotated")).toBeInTheDocument();
    expect(canvas.getByText(/No scrape received yet/)).toBeInTheDocument();
  });

  it("applies persisted reduced motion app-wide at startup, before settings is opened (NIC-141)", async () => {
    const bridge = createMockCerebralBridge();
    bridge.getSettings = () =>
      Promise.resolve({
        schemaVersion: "1.0.0",
        defaultModeId: "executive",
        appearance: { reducedMotion: true, assistantName: "Heimlich" },
        knowledge: { rootReference: null },
        workspace: { windowsStoredByMode: false, mainDisplayId: "system-primary", layoutDisplayId: "system-primary" },
        modeColors: {}
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

  it("stages the assistant name as a draft and renames the dashboard on Save (NIC-137)", async () => {
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
    const input = await within(dialog).findByLabelText("Assistant name");
    expect(input).toHaveValue("Heimlich"); // the mock's persisted (default) name

    // Typing only stages a draft — the dashboard name does NOT change yet.
    fireEvent.change(input, { target: { value: "Nova" } });
    expect(screen.queryByRole("region", { name: "Nova" })).toBeNull();
    expect(screen.getByRole("region", { name: "Heimlich" })).toBeInTheDocument();

    // Save persists + the bridge broadcasts settings.changed → the dashboard re-syncs live.
    fireEvent.click(within(dialog).getByRole("button", { name: "Save" }));
    await waitFor(() => expect(accepted).toEqual([true]));
    expect(await screen.findByRole("region", { name: "Nova" })).toBeInTheDocument();
  });

  it("stages a mode color as a draft and applies it to the dashboard on Save (NIC-137)", async () => {
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
    const primary = await within(dialog).findByLabelText("Executive primary color");
    expect(primary).toHaveValue("#e8b765"); // the shipped default (no override stored)

    // Picking only stages a draft — the mode token is NOT overridden yet.
    fireEvent.change(primary, { target: { value: "#ff0000" } });
    expect(
      document.documentElement.style.getPropertyValue("--ch-mode-executive-primary")
    ).not.toBe("#ff0000");

    // Save persists + broadcasts → the override lands on the document root live.
    fireEvent.click(within(dialog).getByRole("button", { name: "Save" }));
    await waitFor(() => expect(accepted).toEqual([true]));
    await waitFor(() =>
      expect(
        document.documentElement.style.getPropertyValue("--ch-mode-executive-primary")
      ).toBe("#ff0000")
    );
  });

  it("Cancel reverts a staged edit; Restore defaults stages the shipped values (NIC-137)", async () => {
    renderApp();
    const dialog = openSettings();
    fireEvent.click(within(dialog).getByRole("tab", { name: "Customization" }));
    const input = await within(dialog).findByLabelText("Assistant name");

    // Cancel discards the draft.
    fireEvent.change(input, { target: { value: "Nova" } });
    expect(input).toHaveValue("Nova");
    fireEvent.click(within(dialog).getByRole("button", { name: "Cancel" }));
    expect(input).toHaveValue("Heimlich");

    // Restore defaults stages the default name (Heimlich) without needing a change.
    fireEvent.change(input, { target: { value: "Nova" } });
    fireEvent.click(within(dialog).getByRole("button", { name: "Restore defaults" }));
    expect(input).toHaveValue("Heimlich");
  });

  it("tightens confirmation via 'Ask before all actions' and persists an accepted patch (NIC-137)", async () => {
    const { bridge } = renderApp();
    const accepted: boolean[] = [];
    const original = bridge.updateSettings.bind(bridge);
    bridge.updateSettings = async (input) => {
      const result = await original(input);
      accepted.push(result.accepted);
      return result;
    };

    const dialog = openSettings();
    fireEvent.click(within(dialog).getByRole("tab", { name: "Permissions" }));
    const toggle = await within(dialog).findByLabelText("Ask before all actions");
    expect(toggle).not.toBeChecked(); // the mock persists false

    fireEvent.click(toggle);
    expect(toggle).toBeChecked();
    await waitFor(() => expect(accepted).toEqual([true]));
  });

  it("re-syncs the assistant name and mode colors live on a settings.changed event (NIC-137)", () => {
    const { bridge } = renderApp();
    // A change made in the separate native settings window arrives as an event; the
    // dashboard (a different webview) reflects it without a relaunch.
    act(() => {
      bridge.emit({
        eventId: "brevt_settings00000001",
        type: "settings.changed",
        schemaVersion: "1.0.0",
        timestamp: "2026-07-10T16:00:00.000Z",
        payload: {
          settings: {
            schemaVersion: "1.0.0",
            defaultModeId: "executive",
            confirmAllActions: false,
            appearance: { reducedMotion: false, assistantName: "Cerebra" },
            knowledge: { rootReference: null },
            workspace: { windowsStoredByMode: false, mainDisplayId: "system-primary", layoutDisplayId: "system-primary" },
            modeColors: { "executive.primary": "#ff2d55" }
          }
        }
      });
    });
    // The center-stage region re-renders to the new name...
    expect(screen.getByRole("region", { name: "Cerebra" })).toBeInTheDocument();
    // ...and the mode accent override lands on the document root (live re-theme).
    expect(
      document.documentElement.style.getPropertyValue("--ch-mode-executive-primary")
    ).toBe("#ff2d55");
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

  it("chooses the knowledge root through the native Finder picker and persists it (NIC-138)", async () => {
    const postMessage = vi.fn();
    (window as unknown as ShellControlWindow).webkit = {
      messageHandlers: { shellControl: { postMessage } }
    };
    const { SettingsApp } = await import("../../app/SettingsApp");
    render(<SettingsApp />);
    const surface = screen.getByRole("main", { name: "Settings" });

    fireEvent.click(within(surface).getByRole("tab", { name: "Setup" }));
    const browse = await within(surface).findByRole("button", { name: "Browse…" });
    expect(browse).toBeEnabled();
    fireEvent.click(browse);
    expect(postMessage).toHaveBeenCalledWith({ action: "pickKnowledgeRoot" });

    // The native shell posts the chosen folder back; the panel reflects it in the field.
    act(() => {
      (
        window as unknown as { __cerebralKnowledgeRootUpdate?: (path: string) => void }
      ).__cerebralKnowledgeRootUpdate?.("/Users/me/CerebralHelm/knowledge");
    });
    expect(within(surface).getByLabelText("Knowledge root reference")).toHaveValue(
      "/Users/me/CerebralHelm/knowledge"
    );
  });
});
