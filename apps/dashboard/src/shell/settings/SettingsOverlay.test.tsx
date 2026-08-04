import { act, cleanup, render, screen, within, fireEvent, waitFor } from "@testing-library/react";
import { DashboardShell } from "../DashboardShell";
import { SettingsSurface } from "./SettingsOverlay";
import { DashboardStateProvider } from "../../state/DashboardStateProvider";
import { BridgeProvider } from "../../state/BridgeProvider";
import { ActionStatusProvider } from "../../state/ActionStatusProvider";
import { SettingsProvider } from "../../state/SettingsProvider";
import { ReportProvider } from "../../state/ReportProvider";
import { InputProvider } from "../../state/InputProvider";
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
                  <ReportProvider>
                    <InputProvider>
                      <DashboardShell />
                    </InputProvider>
                  </ReportProvider>
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

interface NotesBrowserWindow {
  webkit?: { messageHandlers?: { shellControl?: { postMessage(message: unknown): void } } };
  __cerebralNotesBrowser?: { obsidian?: boolean };
  __cerebralNotesBrowserUpdate?: (outcome: string) => void;
}

function asNotesBrowserWindow(): NotesBrowserWindow {
  return window as unknown as NotesBrowserWindow;
}

function resetNotesBrowserWindow() {
  const target = asNotesBrowserWindow();
  delete target.webkit;
  delete target.__cerebralNotesBrowser;
  delete target.__cerebralNotesBrowserUpdate;
}

/**
 * Render the standalone settings surface and return the "Browse notes" field (NIC-162).
 *
 * Not via the dashboard gear: once a shell-control channel exists, the gear delegates to the
 * native shell instead of opening the in-web dialog — which is exactly the condition these
 * tests need to simulate.
 */
async function renderBrowseNotesField(): Promise<HTMLElement> {
  const bridge = createMockCerebralBridge();
  const store = createBridgeStore(bridge, loadBootstrapState());
  render(
    <BridgeProvider bridge={bridge}>
      <DashboardStateProvider store={store}>
        <AppearanceProvider>
          <ThemeProvider>
            <SettingsProvider surface="standalone">
              <SettingsSurface />
            </SettingsProvider>
          </ThemeProvider>
        </AppearanceProvider>
      </DashboardStateProvider>
    </BridgeProvider>
  );
  fireEvent.click(screen.getByRole("tab", { name: "Setup" }));
  const label = await screen.findByText("Browse notes", { selector: ".settings-field__label" });
  return label.closest(".settings-field") as HTMLElement;
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

    // The change writes the WHOLE calendar→mode map through the settings path — the edited
    // entry plus every mapping the user already had, so saving one row never drops the others.
    await waitFor(() => expect(patches).toHaveLength(1));
    expect(patches[0]).toEqual({
      calendarModeMap: { "cal-work": "developer", "cal-school": "school" }
    });
  });

  it("shows the Canvas pairing token + last-scrape status and disconnects (NIC-132)", async () => {
    renderApp();
    const dialog = openSettings();
    fireEvent.click(within(dialog).getByRole("tab", { name: "Setup" }));

    // Scope to the Canvas card by its label so its Disconnect doesn't clash with other cards.
    const label = await within(dialog).findByText("Canvas (School widgets)");
    const canvas = within(label.closest(".settings-field") as HTMLElement);

    // The pairing token and the last-scrape summary are shown (mock: 2 courses, 2 deadlines).
    expect(await canvas.findByText("mock-canvas-token")).toBeInTheDocument();
    expect(canvas.getByText(/2 courses, 2 deadlines/)).toBeInTheDocument();

    // Disconnect rotates the token and clears the scrape summary (purge + rotate).
    fireEvent.click(canvas.getByRole("button", { name: "Disconnect" }));
    expect(await canvas.findByText("mock-canvas-token-rotated")).toBeInTheDocument();
    expect(canvas.getByText(/No scrape received yet/)).toBeInTheDocument();
  });

  it("hides and unhides a scraped course from the Canvas manage-list (NIC-132)", async () => {
    renderApp();
    const dialog = openSettings();
    fireEvent.click(within(dialog).getByRole("tab", { name: "Setup" }));

    const label = await within(dialog).findByText("Canvas (School widgets)");
    const canvas = within(label.closest(".settings-field") as HTMLElement);

    // The manage-list shows each scraped course with a Hide control (mock: Theory of Computation).
    const hide = await canvas.findByRole("button", { name: "Hide Theory of Computation" });
    // Hiding drops it from the visible count (2 courses → 1) and flips the control to Unhide.
    fireEvent.click(hide);
    expect(await canvas.findByRole("button", { name: "Unhide Theory of Computation" })).toBeInTheDocument();
    expect(canvas.getByText(/1 course, 2 deadlines/)).toBeInTheDocument();

    // Unhiding restores it.
    fireEvent.click(canvas.getByRole("button", { name: "Unhide Theory of Computation" }));
    expect(await canvas.findByRole("button", { name: "Hide Theory of Computation" })).toBeInTheDocument();
    expect(canvas.getByText(/2 courses, 2 deadlines/)).toBeInTheDocument();
  });

  it("names Obsidian as the browse destination and reports where the request went (NIC-162)", async () => {
    const posted: unknown[] = [];
    const target = asNotesBrowserWindow();
    // Stand in for the native host: a shell-control channel, and Obsidian installed.
    // Rendered as the standalone settings surface, because with a native channel
    // present the dashboard gear delegates to the shell instead of opening a dialog.
    target.webkit = { messageHandlers: { shellControl: { postMessage: (m) => posted.push(m) } } };
    target.__cerebralNotesBrowser = { obsidian: true };

    try {
      const card = within(await renderBrowseNotesField());

      // The button names its destination before the click, not after.
      fireEvent.click(card.getByRole("button", { name: "Open in Obsidian" }));
      expect(posted).toEqual([{ action: "browseKnowledgeRoot" }]);

      // Obsidian silently ignores a folder it has not registered as a vault, so the
      // outcome carries that hint rather than implying the notes are now on screen.
      act(() => target.__cerebralNotesBrowserUpdate?.("obsidian"));
      expect(await card.findByText(/Add the folder as a vault in Obsidian first/)).toBeInTheDocument();

      // A Finder fallback says why it happened.
      act(() => target.__cerebralNotesBrowserUpdate?.("finder"));
      expect(await card.findByText(/Obsidian isn't installed/)).toBeInTheDocument();
    } finally {
      resetNotesBrowserWindow();
    }
  });

  it("offers Finder when Obsidian is absent, and disables browsing off the macOS host (NIC-162)", async () => {
    // No native channel at all (a plain browser): the action is honestly disabled.
    const plain = within(await renderBrowseNotesField());
    expect(plain.getByText("Browsing your notes requires the macOS host")).toBeInTheDocument();
    cleanup();

    // On the host without Obsidian, the button promises Finder — not Obsidian.
    const target = asNotesBrowserWindow();
    target.webkit = { messageHandlers: { shellControl: { postMessage: () => {} } } };
    target.__cerebralNotesBrowser = { obsidian: false };
    try {
      const card = within(await renderBrowseNotesField());
      expect(card.getByRole("button", { name: "Reveal in Finder" })).toBeInTheDocument();
      expect(card.queryByRole("button", { name: "Open in Obsidian" })).toBeNull();
    } finally {
      resetNotesBrowserWindow();
    }
  });

  it("shows the note count, the source root, and the most recent notes (NIC-162)", async () => {
    renderApp();
    const dialog = openSettings();
    fireEvent.click(within(dialog).getByRole("tab", { name: "Setup" }));

    const label = await within(dialog).findByText("Your notes", {
      selector: ".settings-field__label"
    });
    const card = within(label.closest(".settings-field") as HTMLElement);

    // Five: the two general notes plus STAT 240's three (added with take-notes in phase 5 —
    // a course note is an ordinary note, so it counts in the library like any other).
    expect(await card.findByText("5 notes")).toBeInTheDocument();
    expect(card.getByText("/Users/you/CerebralHelm/knowledge")).toBeInTheDocument();
    // A note written outside CerebralHelm is listed like any other, titled by filename.
    expect(card.getByText("Hull Plating")).toBeInTheDocument();
    expect(card.getByText("Atlas kickoff")).toBeInTheDocument();
  });

  it("distinguishes an empty library from an unreadable knowledge root (NIC-162)", async () => {
    const bridge = createMockCerebralBridge();
    const store = createBridgeStore(bridge, loadBootstrapState());
    bridge.listNotes = () =>
      Promise.resolve({ available: true, root: "/Users/me/knowledge", total: 0, notes: [] });
    render(
      <BridgeProvider bridge={bridge}>
        <DashboardStateProvider store={store}>
          <AppearanceProvider>
            <ThemeProvider>
              <ActionStatusProvider>
                <SettingsProvider>
                  <ReportProvider>
                    <InputProvider>
                      <DashboardShell />
                    </InputProvider>
                  </ReportProvider>
                </SettingsProvider>
              </ActionStatusProvider>
            </ThemeProvider>
          </AppearanceProvider>
        </DashboardStateProvider>
      </BridgeProvider>
    );
    const dialog = openSettings();
    fireEvent.click(within(dialog).getByRole("tab", { name: "Setup" }));

    const label = await within(dialog).findByText("Your notes", {
      selector: ".settings-field__label"
    });
    const card = within(label.closest(".settings-field") as HTMLElement);

    // An empty root is empty at a named location — not an error, and not silence.
    expect(await card.findByText("No notes yet")).toBeInTheDocument();
    expect(card.getByText("/Users/me/knowledge")).toBeInTheDocument();
    expect(card.queryByText(/could not be read/)).toBeNull();
  });

  it("says so when the knowledge root cannot be read, rather than showing it empty (NIC-162)", async () => {
    const bridge = createMockCerebralBridge();
    const store = createBridgeStore(bridge, loadBootstrapState());
    bridge.listNotes = () => Promise.resolve({ available: false, root: "", total: 0, notes: [] });
    render(
      <BridgeProvider bridge={bridge}>
        <DashboardStateProvider store={store}>
          <AppearanceProvider>
            <ThemeProvider>
              <ActionStatusProvider>
                <SettingsProvider>
                  <ReportProvider>
                    <InputProvider>
                      <DashboardShell />
                    </InputProvider>
                  </ReportProvider>
                </SettingsProvider>
              </ActionStatusProvider>
            </ThemeProvider>
          </AppearanceProvider>
        </DashboardStateProvider>
      </BridgeProvider>
    );
    const dialog = openSettings();
    fireEvent.click(within(dialog).getByRole("tab", { name: "Setup" }));

    const label = await within(dialog).findByText("Your notes", {
      selector: ".settings-field__label"
    });
    const card = within(label.closest(".settings-field") as HTMLElement);

    expect(await card.findByText("Your knowledge root could not be read")).toBeInTheDocument();
    expect(card.queryByText("No notes yet")).toBeNull();
  });

  it("reports the rebuild as unavailable in the browser preview, never a fake success (NIC-163)", async () => {
    renderApp();
    const dialog = openSettings();
    fireEvent.click(within(dialog).getByRole("tab", { name: "Setup" }));

    // Scope by the field's label element — the button carries the same text.
    const label = await within(dialog).findByText("Rebuild index", {
      selector: ".settings-field__label"
    });
    const card = within(label.closest(".settings-field") as HTMLElement);

    // The mock bridge has no knowledge root, so it reports rebuilt: false — the card
    // must say the surface is unavailable rather than "Rebuilt · 0 notes indexed".
    fireEvent.click(card.getByRole("button", { name: "Rebuild index" }));
    expect(await card.findByText("Requires the macOS host")).toBeInTheDocument();
    expect(card.queryByText(/Rebuilt/)).toBeNull();
  });

  it("reports how many notes a rebuild indexed, and says so when one fails (NIC-163)", async () => {
    const bridge = createMockCerebralBridge();
    const store = createBridgeStore(bridge, loadBootstrapState());
    let attempt = 0;
    bridge.rebuildKnowledgeIndex = () => {
      attempt += 1;
      return attempt === 1
        ? Promise.resolve({ rebuilt: true, root: "/Users/me/knowledge", noteCount: 12 })
        : Promise.reject(new Error("index write failed"));
    };
    render(
      <BridgeProvider bridge={bridge}>
        <DashboardStateProvider store={store}>
          <AppearanceProvider>
            <ThemeProvider>
              <ActionStatusProvider>
                <SettingsProvider>
                  <ReportProvider>
                    <InputProvider>
                      <DashboardShell />
                    </InputProvider>
                  </ReportProvider>
                </SettingsProvider>
              </ActionStatusProvider>
            </ThemeProvider>
          </AppearanceProvider>
        </DashboardStateProvider>
      </BridgeProvider>
    );
    const dialog = openSettings();
    fireEvent.click(within(dialog).getByRole("tab", { name: "Setup" }));

    // Scope by the field's label element — the button carries the same text.
    const label = await within(dialog).findByText("Rebuild index", {
      selector: ".settings-field__label"
    });
    const card = within(label.closest(".settings-field") as HTMLElement);

    // Success reports what the rebuild actually covered, not a bare "done".
    fireEvent.click(card.getByRole("button", { name: "Rebuild index" }));
    expect(await card.findByText("Rebuilt · 12 notes indexed")).toBeInTheDocument();

    // A failure is reported as one, and promises the Markdown was left alone.
    fireEvent.click(card.getByRole("button", { name: "Rebuild index" }));
    expect(await card.findByText("Rebuild failed. Your notes are unchanged.")).toBeInTheDocument();
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
                  <ReportProvider>
                    <InputProvider>
                      <DashboardShell />
                    </InputProvider>
                  </ReportProvider>
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

  it("the pinned shutdown control dispatches the same confirmation-gated shut-down workflow", () => {
    // The control is macOS-only, so it only becomes live once a shell-control channel exists.
    const postMessage = vi.fn();
    (window as unknown as ShellControlWindow).webkit = {
      messageHandlers: { shellControl: { postMessage } }
    };

    const bridge = createMockCerebralBridge();
    const submissions: string[] = [];
    const spyBridge = {
      ...bridge,
      submitCommand(input: { rawInput: string; source: string }) {
        submissions.push(input.rawInput);
        return bridge.submitCommand(input);
      }
    };
    const store = createBridgeStore(spyBridge, loadBootstrapState());
    render(
      <BridgeProvider bridge={spyBridge}>
        <DashboardStateProvider store={store}>
          <AppearanceProvider>
            <ThemeProvider>
              <SettingsProvider surface="standalone">
                <SettingsSurface />
              </SettingsProvider>
            </ThemeProvider>
          </AppearanceProvider>
        </DashboardStateProvider>
      </BridgeProvider>
    );

    const quit = screen.getByRole("button", { name: /Shut down CerebralHelm/ });
    expect(quit).toBeEnabled();
    fireEvent.click(quit);

    // Not a direct native quit: it dispatches the same workflow the Executive `shut-down` slot
    // does, so app.quit's destructive risk class gates this control identically. A settings
    // control that quit directly would be an unconfirmed second door to the same action.
    expect(submissions).toEqual(["run shut-down"]);
    expect(postMessage).not.toHaveBeenCalledWith(expect.objectContaining({ action: "quit" }));
  });

  it("the standalone surface rebinds the palette shortcut and closes via the native channel", async () => {
    const postMessage = vi.fn();
    (window as unknown as ShellControlWindow).webkit = {
      messageHandlers: { shellControl: { postMessage } }
    };
    const { SettingsApp } = await import("../../app/SettingsApp");
    render(<SettingsApp />);
    const surface = screen.getByRole("main", { name: "Settings" });

    // The summon shortcut lives in General (the default tab); it seeds once the read settles.
    // It now opens the sidebar rather than the palette (owner decision, 2026-08-03), hence the
    // control's label — the shellControl action keeps its `setPaletteShortcut` name because that
    // is also the durable persistence key, and renaming it would reset every stored binding.
    const select = await within(surface).findByRole("combobox", { name: "Sidebar shortcut" });
    fireEvent.change(select, { target: { value: "command-shift-space" } });
    expect(postMessage).toHaveBeenCalledWith({
      action: "setPaletteShortcut",
      preset: "command-shift-space"
    });

    fireEvent.click(within(surface).getByRole("button", { name: "Close settings" }));
    expect(postMessage).toHaveBeenCalledWith({ action: "closeSettings" });
  });

  it("drives the sidebar's edge reveal through the shell, and gates sensitivity on it", async () => {
    const postMessage = vi.fn();
    (window as unknown as ShellControlWindow).webkit = {
      messageHandlers: { shellControl: { postMessage } }
    };
    const { SettingsApp } = await import("../../app/SettingsApp");
    render(<SettingsApp />);
    const surface = screen.getByRole("main", { name: "Settings" });

    // Both controls are shell state (UserDefaults), not settings-snapshot fields, so they travel
    // over shellControl rather than the settings patch.
    const sensitivity = await within(surface).findByRole("combobox", { name: "Edge sensitivity" });
    fireEvent.change(sensitivity, { target: { value: "relaxed" } });
    expect(postMessage).toHaveBeenCalledWith({ action: "setSidebarEdge", dwell: "relaxed" });

    const toggle = within(surface).getByRole("checkbox", { name: "Reveal at screen edge" });
    fireEvent.click(toggle);
    expect(postMessage).toHaveBeenCalledWith({ action: "setSidebarEdge", enabled: false });

    // Turning the reveal off leaves the dwell control visible but inert — a dead setting should
    // read as unavailable rather than silently doing nothing.
    expect(within(surface).getByRole("combobox", { name: "Edge sensitivity" })).toBeDisabled();
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
