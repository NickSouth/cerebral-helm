import { act, render, screen, within, fireEvent, waitFor } from "@testing-library/react";
import { DashboardShell } from "../shell/DashboardShell";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { BridgeProvider } from "../state/BridgeProvider";
import { ActionStatusProvider } from "../state/ActionStatusProvider";
import { SettingsProvider } from "../state/SettingsProvider";
import { ReportProvider } from "../state/ReportProvider";
import { InputProvider } from "../state/InputProvider";
import { AppearanceProvider } from "../state/AppearanceProvider";
import { ThemeProvider } from "../app/ThemeProvider";
import { createBridgeStore } from "../state/bridgeStore";
import { createMockCerebralBridge, loadBootstrapState } from "../bridge/mockCerebralBridge";
import {
  initialValues,
  missingRequired,
  renderableFields,
  type InputField,
  type InputForm
} from "./inputForm";
import { clearSportsEventsCache } from "../sports/sportsEvents";

/** The Input region and its field schema (docs/quick-actions/PLAN.md phase 3). */

// The sports read is cached module-wide so the picker and the report it opens share one fetch.
// That cache outlives a test, so each one starts from a clean read rather than the previous
// test's events.
beforeEach(() => clearSportsEventsCache());

function renderShell(bridgeOverrides: Partial<ReturnType<typeof createMockCerebralBridge>> = {}) {
  const base = createMockCerebralBridge();
  const bridge = { ...base, ...bridgeOverrides } as ReturnType<typeof createMockCerebralBridge>;
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

function openCaptureNote() {
  fireEvent.click(screen.getByRole("button", { name: "Capture note" }));
  return screen.getByRole("region", { name: "Capture note form" });
}

describe("Input region", () => {
  it("is absent until an Input action opens it", () => {
    renderShell();
    expect(screen.queryByRole("region", { name: "Capture note form" })).toBeNull();
  });

  it("toggles closed when its own slot is pressed again", () => {
    renderShell();
    openCaptureNote();
    fireEvent.click(screen.getByRole("button", { name: "Capture note" }));
    expect(screen.queryByRole("region", { name: "Capture note form" })).toBeNull();
  });

  it("keeps the quick-action grid and the running field in place — it is a panel, not a takeover", () => {
    renderShell();
    openCaptureNote();
    expect(screen.getByRole("region", { name: "Heimlich" })).toBeInTheDocument();
    expect(screen.getByRole("group", { name: "Quick actions" })).toBeInTheDocument();
  });

  it("discards the form when the mode changes, rather than carrying typing into another mode", async () => {
    const { bridge } = renderShell();
    const form = openCaptureNote();
    fireEvent.change(within(form).getByLabelText(/Title/), { target: { value: "Half-written" } });

    await waitFor(async () => {
      await bridge.applyMode({ modeId: "developer" });
    });
    await waitFor(() =>
      expect(screen.queryByRole("region", { name: "Capture note form" })).toBeNull()
    );
  });

  it("keeps the form and the typing when a submit fails", async () => {
    // Losing what the user wrote because a write failed would be the worst possible response.
    const { ...rest } = renderShell({
      captureNote: () => Promise.reject(new Error("bridge down"))
    });
    void rest;
    const form = openCaptureNote();
    fireEvent.change(within(form).getByLabelText(/Title/), { target: { value: "Keep me" } });
    fireEvent.click(within(form).getByRole("button", { name: "Capture" }));

    const status = document.querySelector(".action-status") as HTMLElement;
    await waitFor(() => expect(status).toHaveTextContent(/failed/i));
    expect(screen.getByRole("region", { name: "Capture note form" })).toBeInTheDocument();
    expect(within(form).getByLabelText(/Title/)).toHaveValue("Keep me");
  });

  it("cancels without writing anything", () => {
    const submissions: string[] = [];
    renderShell({
      captureNote: (input: { title: string }) => {
        submissions.push(input.title);
        return Promise.resolve({ noteId: "note_x" });
      }
    } as never);
    const form = openCaptureNote();
    fireEvent.change(within(form).getByLabelText(/Title/), { target: { value: "Never sent" } });
    fireEvent.click(within(form).getByRole("button", { name: "Cancel" }));

    expect(screen.queryByRole("region", { name: "Capture note form" })).toBeNull();
    expect(submissions).toEqual([]);
  });
});

describe("create-event in the region", () => {
  function openCreateEvent() {
    fireEvent.click(screen.getByRole("button", { name: "Create event" }));
    return screen.findByRole("region", { name: "Create event form" });
  }

  it("waits for the persisted mapping before seeding, so the mode-aware default survives", async () => {
    // Both halves of this were real bugs. The form must not be built before `getSettings`
    // resolves — the body seeds its values once, so a default arriving later is silently lost.
    renderShell();
    await openCreateEvent();

    const calendar = (await screen.findByLabelText("Calendar")) as HTMLSelectElement;
    await waitFor(() => expect(calendar.value).toBe("cal-work"));
  });

  it("renders the preselected option once the provider's options arrive", async () => {
    // The other half: the seeded id has no matching <option> on first render, so the select
    // would fall back to the first option and never recover.
    renderShell();
    await openCreateEvent();

    const calendar = (await screen.findByLabelText("Calendar")) as HTMLSelectElement;
    await waitFor(() =>
      expect(calendar.selectedOptions[0]?.textContent).toBe("Work")
    );
    // "Default calendar" stays available — writing nowhere in particular is a real choice.
    expect([...calendar.options].map((option) => option.textContent)).toContain("Default calendar");
  });

  it("offers the default calendar when the active mode maps to none", async () => {
    // Entertainment is unmapped in the mock. Guessing at one of the user's calendars would put
    // an event somewhere they never chose.
    const { bridge } = renderShell();
    await act(async () => {
      await bridge.applyMode({ modeId: "entertainment" });
    });

    fireEvent.click(screen.getByRole("button", { name: "Create event" }));
    const calendar = (await screen.findByLabelText("Calendar")) as HTMLSelectElement;
    await waitFor(() => expect(calendar.selectedOptions[0]?.textContent).toBe("Default calendar"));
  });

  it("preselects the active mode and offers the others — no blank choice", async () => {
    // The tag this writes is what decides which mode's schedule shows the event, so leaving it
    // unanswered is not a real option the way "Default calendar" is.
    renderShell();
    const region = await openCreateEvent();

    // Scoped to the form: the right rail's MODE panel carries the same word.
    const modeField = within(region).getByLabelText("Mode") as HTMLSelectElement;
    await waitFor(() => expect(modeField.value).toBe("executive"));
    const labels = [...modeField.options].map((option) => option.textContent);
    expect(labels).toEqual(["Executive", "Developer", "School", "Entertainment"]);
  });

  it("writes the chosen mode's tag into the notes", async () => {
    // Without it, an event created in a mode with no mapped calendar falls to the default mode
    // and disappears from the mode it was made in.
    const created: { notes?: string }[] = [];
    renderShell({
      createCalendarEvent: (input) => {
        created.push(input);
        return Promise.resolve({
          eventId: "evt_1",
          calendarTitle: "Work",
          awaitingConfirmation: false
        });
      }
    });
    const region = await openCreateEvent();

    fireEvent.change(within(region).getByLabelText(/Event/), { target: { value: "Stats final" } });
    fireEvent.change(within(region).getByLabelText("Mode"), { target: { value: "school" } });
    await act(async () => {
      fireEvent.click(within(region).getByRole("button", { name: "Create" }));
    });

    await waitFor(() => expect(created).toHaveLength(1));
    expect(created[0].notes).toBe("#school");
  });

  it("seeds a usable range and blocks only on the title", async () => {
    renderShell();
    const region = await openCreateEvent();

    expect((within(region).getByLabelText("When starts") as HTMLInputElement).value).not.toBe("");
    expect((within(region).getByLabelText("When ends") as HTMLInputElement).value).not.toBe("");

    const submit = within(region).getByRole("button", { name: "Create" });
    expect(submit).toBeDisabled();
    expect(submit).toHaveAttribute("title", "Event required");

    fireEvent.change(within(region).getByLabelText(/Event/), { target: { value: "Board prep" } });
    expect(within(region).getByRole("button", { name: "Create" })).toBeEnabled();
  });

  it("carries the end forward when the start is dragged past it", async () => {
    // Submitting a backwards range is rejected by the tool; the control simply never produces
    // one rather than validating after the fact.
    renderShell();
    const region = await openCreateEvent();
    const start = within(region).getByLabelText("When starts");
    const end = within(region).getByLabelText("When ends") as HTMLInputElement;

    fireEvent.change(start, { target: { value: "2027-01-01T20:00" } });
    expect(end.value).toBe("2027-01-01T20:00");
  });
});

describe("search-youtube in the region", () => {
  async function openSearchYouTube() {
    const { bridge, submitted } = (() => {
      const submitted: string[] = [];
      const rendered = renderShell({
        submitCommand: (input: { rawInput: string }) => {
          submitted.push(input.rawInput);
          return Promise.resolve({ commandId: "cmd_1", accepted: true });
        }
      });
      return { bridge: rendered.bridge, submitted };
    })();

    // The slot lives in Entertainment, not the default mode.
    await act(async () => {
      await bridge.applyMode({ modeId: "entertainment" });
    });
    fireEvent.click(screen.getByRole("button", { name: "Search YouTube" }));
    return { submitted, region: await screen.findByRole("region", { name: "Search YouTube form" }) };
  }

  it("dispatches the youtube verb, so the adapter — not the query — owns the destination", async () => {
    const { submitted, region } = await openSearchYouTube();

    fireEvent.change(within(region).getByLabelText("Search *"), { target: { value: "  lo-fi mix  " } });
    await act(async () => {
      fireEvent.click(within(region).getByRole("button", { name: "Search" }));
    });

    await waitFor(() => expect(submitted).toEqual(["youtube lo-fi mix"]));
  });

  it("blocks on an empty query rather than dispatching a bare search", async () => {
    const { submitted, region } = await openSearchYouTube();
    expect(within(region).getByRole("button", { name: "Search" })).toBeDisabled();
    expect(submitted).toEqual([]);
  });

  it("reports the search as dispatched, never as opened", async () => {
    // The receipt says the command was accepted and nothing more; the tool is macOS-only, so
    // claiming a page opened would be a fabricated success off the host.
    const { region } = await openSearchYouTube();
    fireEvent.change(within(region).getByLabelText("Search *"), { target: { value: "guitar tuning" } });
    await act(async () => {
      fireEvent.click(within(region).getByRole("button", { name: "Search" }));
    });

    const status = document.querySelector(".action-status") as HTMLElement;
    await waitFor(() => expect(status).toHaveTextContent(/Searching YouTube for/));
    expect(status).not.toHaveTextContent(/Opened/);
  });
});

describe("git-clone in the region", () => {
  async function openGitClone(overrides: Parameters<typeof renderShell>[0] = {}) {
    const { bridge } = renderShell(overrides);
    // The slot lives in Developer.
    await act(async () => {
      await bridge.applyMode({ modeId: "developer" });
    });
    fireEvent.click(screen.getByRole("button", { name: "Clone repo" }));
    return screen.findByRole("region", { name: "Clone repo form" });
  }

  it("joins the picked location with the repository name — the picker chooses the PARENT", async () => {
    // An open panel selects folders that already exist; a clone target must not. So the panel
    // picks where to put it, and the repo gets its own folder inside that.
    const sent: { repositoryUrl: string; directory?: string }[] = [];
    const region = await openGitClone({
      cloneRepository: (input) => {
        sent.push(input);
        return Promise.resolve({
          clonedPath: "/Users/example/Projects/CerebralHelm/repo",
          repositoryName: "repo",
          awaitingConfirmation: false
        });
      },
      chooseFolder: () =>
        Promise.resolve({
          folderPath: "/Users/example/Projects/CerebralHelm",
          relativeFolder: "CerebralHelm",
          cancelled: false,
          outsideRoot: false,
          available: true
        })
    });

    await act(async () => {
      fireEvent.click(within(region).getByRole("button", { name: "Choose…" }));
    });
    await waitFor(() =>
      expect(within(region).getByLabelText(/Location/)).toHaveValue("CerebralHelm")
    );

    fireEvent.change(within(region).getByLabelText(/Repository/), {
      target: { value: "https://github.com/owner/repo.git" }
    });
    await act(async () => {
      fireEvent.click(within(region).getByRole("button", { name: "Clone" }));
    });

    await waitFor(() => expect(sent).toHaveLength(1));
    expect(sent[0].directory).toBe("CerebralHelm/repo");
  });

  it("explains a refused folder rather than silently ignoring it", async () => {
    // Cancelling and being refused are different: the user did choose something here.
    const region = await openGitClone({
      chooseFolder: () =>
        Promise.resolve({
          folderPath: null,
          relativeFolder: null,
          cancelled: false,
          outsideRoot: true,
          available: true
        })
    });

    await act(async () => {
      fireEvent.click(within(region).getByRole("button", { name: "Choose…" }));
    });
    await waitFor(() =>
      expect(within(region).getByText(/outside your projects folder/)).toBeInTheDocument()
    );
    expect(within(region).getByLabelText(/Location/)).toHaveValue("");
  });

  it("drops the Choose button where there is no panel, leaving the field typeable", async () => {
    // The browser preview has no Finder. A button that silently does nothing would be worse than
    // no button — the typed field still works.
    const region = await openGitClone();
    await act(async () => {
      fireEvent.click(within(region).getByRole("button", { name: "Choose…" }));
    });
    await waitFor(() =>
      expect(within(region).queryByRole("button", { name: "Choose…" })).toBeNull()
    );

    fireEvent.change(within(region).getByLabelText(/Location/), { target: { value: "typed" } });
    expect(within(region).getByLabelText(/Location/)).toHaveValue("typed");
  });

  it("sends the URL and omits a blank folder, letting the host derive one", async () => {
    const sent: { repositoryUrl: string; directory?: string }[] = [];
    const region = await openGitClone({
      cloneRepository: (input) => {
        sent.push(input);
        return Promise.resolve({
          clonedPath: "/Users/example/Projects/repo",
          repositoryName: "repo",
          awaitingConfirmation: false
        });
      }
    });

    fireEvent.change(within(region).getByLabelText(/Repository/), {
      target: { value: "  https://github.com/owner/repo.git  " }
    });
    await act(async () => {
      fireEvent.click(within(region).getByRole("button", { name: "Clone" }));
    });

    await waitFor(() => expect(sent).toHaveLength(1));
    expect(sent[0]).toEqual({ repositoryUrl: "https://github.com/owner/repo.git", directory: undefined });
  });

  it("blocks on an empty URL — the folder alone is not a clone", async () => {
    const region = await openGitClone();
    expect(within(region).getByRole("button", { name: "Clone" })).toBeDisabled();

    fireEvent.change(within(region).getByLabelText(/Location/), { target: { value: "somewhere" } });
    expect(within(region).getByRole("button", { name: "Clone" })).toBeDisabled();
  });

  it("never claims 'cloned' while a confirmation is still pending", async () => {
    // The gated case: any invocation while "ask before all actions" is on.
    const region = await openGitClone({
      cloneRepository: () =>
        Promise.resolve({ clonedPath: "cmd_1", repositoryName: "", awaitingConfirmation: true })
    });

    fireEvent.change(within(region).getByLabelText(/Repository/), {
      target: { value: "https://github.com/owner/repo.git" }
    });
    await act(async () => {
      fireEvent.click(within(region).getByRole("button", { name: "Clone" }));
    });

    const status = document.querySelector(".action-status") as HTMLElement;
    await waitFor(() => expect(status).toHaveTextContent(/needs your confirmation/));
    expect(status).not.toHaveTextContent(/Cloned into/);
  });
});

describe("create-ticket in the region", () => {
  async function openCreateTicket(overrides: Parameters<typeof renderShell>[0] = {}) {
    const { bridge } = renderShell(overrides);
    await act(async () => {
      await bridge.applyMode({ modeId: "developer" });
    });
    fireEvent.click(screen.getByRole("button", { name: "Create ticket" }));
    return screen.findByRole("region", { name: "Create ticket form" });
  }

  it("asks for a team rather than inferring one, even with a single team", async () => {
    // A silent "use the first team" keeps working right up until a second team exists, and then
    // files tickets somewhere they were never meant to go.
    const region = await openCreateTicket();
    const team = (await within(region).findByLabelText(/Team/)) as HTMLSelectElement;
    await waitFor(() =>
      expect([...team.options].map((option) => option.textContent)).toContain(
        "CerebralHelm Development"
      )
    );
    // With exactly one real option there is no decision to make, so the field makes it — the
    // dropdown stays visible and overridable, but nobody clicks through a list of one.
    await waitFor(() => expect(team.value).toBe("team-nic"));
  });

  it("still asks when there is more than one team", async () => {
    // The auto-selection is "there is no alternative", not "pick the first" — with two teams it
    // stays blank rather than guessing.
    const region = await openCreateTicket({
      listLinearOptions: () =>
        Promise.resolve({
          teams: [
            { id: "a", key: "A", name: "Team A", projects: [], labels: [] },
            { id: "b", key: "B", name: "Team B", projects: [], labels: [] }
          ],
          available: true,
          reason: null
        })
    });
    const team = (await within(region).findByLabelText(/Team/)) as HTMLSelectElement;
    await waitFor(() => expect([...team.options]).toHaveLength(3));
    expect(team.value).toBe("");
    expect(within(region).getByRole("button", { name: "Create" })).toBeDisabled();
  });

  it("scopes projects and labels to the chosen team", async () => {
    const region = await openCreateTicket();
    const team = (await within(region).findByLabelText(/Team/)) as HTMLSelectElement;
    fireEvent.change(team, { target: { value: "team-nic" } });

    const project = within(region).getByLabelText("Project") as HTMLSelectElement;
    const labels = within(region).getByRole("group", { name: /Labels/ }) as HTMLElement;
    await waitFor(() =>
      expect([...project.options].map((option) => option.textContent)).toEqual([
        "No project",
        "CerebralHelm"
      ])
    );
    // Labels are a checkbox group, not a dropdown — an issue routinely carries several.
    expect(within(labels).getByLabelText("MVP Polish")).toBeInTheDocument();
    expect(within(labels).getByLabelText("Tech Debt")).toBeInTheDocument();
  });

  it("offers nothing scoped until a team is chosen, rather than guessing", async () => {
    const region = await openCreateTicket({
      listLinearOptions: () =>
        Promise.resolve({
          teams: [
            { id: "a", key: "A", name: "Team A", projects: [{ id: "pa", name: "Alpha" }], labels: [] },
            { id: "b", key: "B", name: "Team B", projects: [{ id: "pb", name: "Beta" }], labels: [] }
          ],
          available: true,
          reason: null
        })
    });
    const project = (await within(region).findByLabelText("Project")) as HTMLSelectElement;
    // Two teams, no selection: a flat list would offer both projects and produce a write Linear
    // rejects.
    expect([...project.options].map((option) => option.textContent)).toEqual(["No project"]);

    fireEvent.change(within(region).getByLabelText(/Team/), { target: { value: "b" } });
    await waitFor(() =>
      expect([...project.options].map((option) => option.textContent)).toEqual(["No project", "Beta"])
    );
  });

  it("sends the chosen ids with their labels, so a confirmation can name them", async () => {
    const sent: Record<string, unknown>[] = [];
    const region = await openCreateTicket({
      createLinearIssue: (input) => {
        sent.push(input as unknown as Record<string, unknown>);
        return Promise.resolve({ identifier: "NIC-9", url: null, awaitingConfirmation: false });
      }
    });

    await within(region).findByLabelText(/Team/);
    fireEvent.change(within(region).getByLabelText(/Team/), { target: { value: "team-nic" } });
    fireEvent.change(within(region).getByLabelText(/Title/), { target: { value: "  Fix it  " } });
    await waitFor(() => expect(within(region).getByLabelText("Tech Debt")).toBeInTheDocument());
    fireEvent.click(within(region).getByLabelText("Tech Debt"));
    fireEvent.click(within(region).getByLabelText("MVP Polish"));
    fireEvent.change(within(region).getByLabelText("Priority"), { target: { value: "2" } });

    await act(async () => {
      fireEvent.click(within(region).getByRole("button", { name: "Create" }));
    });

    await waitFor(() => expect(sent).toHaveLength(1));
    expect(sent[0]).toMatchObject({
      title: "Fix it",
      teamId: "team-nic",
      teamName: "CerebralHelm Development",
      // Packed back in option order, not click order, so the value reads like the list.
      labelIds: ["label-polish", "label-debt"],
      labelNames: ["MVP Polish", "Tech Debt"],
      priority: 2
    });
    // An unchosen project is omitted entirely rather than sent as an empty string.
    expect(sent[0].projectId).toBeUndefined();
  });

  it("says the workspace could not be read rather than showing empty dropdowns", async () => {
    // "You have no teams" and "we could not read your teams" are different facts.
    const region = await openCreateTicket({
      listLinearOptions: () =>
        Promise.resolve({ teams: [], available: true, reason: "unauthorized" })
    });
    await waitFor(() =>
      expect(within(region).getAllByText(/Linear workspace couldn’t be read/).length).toBeGreaterThan(0)
    );
  });
});

describe("create-playlist in the region", () => {
  async function openCreatePlaylist(overrides: Parameters<typeof renderShell>[0] = {}) {
    const { bridge } = renderShell(overrides);
    await act(async () => {
      await bridge.applyMode({ modeId: "entertainment" });
    });
    fireEvent.click(screen.getByRole("button", { name: "Create playlist" }));
    return screen.findByRole("region", { name: "Create playlist form" });
  }

  it("defaults to private — Spotify's own default is public", async () => {
    const sent: { name: string; isPublic?: boolean }[] = [];
    const region = await openCreatePlaylist({
      createSpotifyPlaylist: (input) => {
        sent.push(input);
        return Promise.resolve({
          playlistId: "p1",
          name: input.name,
          url: null,
          awaitingConfirmation: false,
          needsReconnect: false
        });
      }
    });

    expect((within(region).getByLabelText("Visibility") as HTMLSelectElement).value).toBe("private");
    fireEvent.change(within(region).getByLabelText(/Name/), { target: { value: "  Late night  " } });
    await act(async () => {
      fireEvent.click(within(region).getByRole("button", { name: "Create" }));
    });

    await waitFor(() => expect(sent).toHaveLength(1));
    expect(sent[0]).toMatchObject({ name: "Late night", isPublic: false });
  });

  it("sends public only when the user chose it", async () => {
    const sent: { isPublic?: boolean }[] = [];
    const region = await openCreatePlaylist({
      createSpotifyPlaylist: (input) => {
        sent.push(input);
        return Promise.resolve({
          playlistId: "p1", name: "x", url: null, awaitingConfirmation: false, needsReconnect: false
        });
      }
    });
    fireEvent.change(within(region).getByLabelText(/Name/), { target: { value: "Shared" } });
    fireEvent.change(within(region).getByLabelText("Visibility"), { target: { value: "public" } });
    await act(async () => {
      fireEvent.click(within(region).getByRole("button", { name: "Create" }));
    });
    await waitFor(() => expect(sent[0].isPublic).toBe(true));
  });

  it("tells the user to reconnect when the grant predates the playlist scopes", async () => {
    // The one failure with a one-step remedy. A generic "something went wrong" would leave the
    // user thinking their Spotify account is broken, when playback still works fine.
    const region = await openCreatePlaylist({
      createSpotifyPlaylist: () =>
        Promise.reject(Object.assign(new Error("denied"), { code: "spotify_reconnect_required" }))
    });
    fireEvent.change(within(region).getByLabelText(/Name/), { target: { value: "Anything" } });
    await act(async () => {
      fireEvent.click(within(region).getByRole("button", { name: "Create" }));
    });

    const status = document.querySelector(".action-status") as HTMLElement;
    await waitFor(() => expect(status).toHaveTextContent(/reconnecting/i));
    // A failed submit keeps the form and the typing.
    expect(within(region).getByLabelText(/Name/)).toHaveValue("Anything");
  });
});

describe("create-project in the region", () => {
  async function openCreateProject(overrides: Parameters<typeof renderShell>[0] = {}) {
    renderShell(overrides);
    // The slot lives in Executive, the default mode.
    fireEvent.click(screen.getByRole("button", { name: "Create project" }));
    return screen.findByRole("region", { name: "Create project form" });
  }

  it("sends the name, the picked location and the importance", async () => {
    const sent: { name: string; location?: string; importance?: number }[] = [];
    const region = await openCreateProject({
      scaffoldProject: (input) => {
        sent.push(input);
        return Promise.resolve({
          projectPath: "/Users/example/Projects/CerebralHelm/Helm",
          awaitingConfirmation: false
        });
      },
      chooseFolder: () =>
        Promise.resolve({
          folderPath: "/Users/example/Projects/CerebralHelm",
          relativeFolder: "CerebralHelm",
          cancelled: false,
          outsideRoot: false,
          available: true
        })
    });

    fireEvent.change(within(region).getByLabelText(/Name/), { target: { value: "  Helm  " } });
    await act(async () => {
      fireEvent.click(within(region).getByRole("button", { name: "Choose…" }));
    });
    await waitFor(() =>
      expect(within(region).getByLabelText(/Location/)).toHaveValue("CerebralHelm")
    );
    await act(async () => {
      fireEvent.click(within(region).getByRole("button", { name: "Create" }));
    });

    await waitFor(() => expect(sent).toHaveLength(1));
    // The name is NOT pre-joined onto the location here — the host owns that join, so the naming
    // rule lives in one place.
    expect(sent[0]).toMatchObject({ name: "Helm", location: "CerebralHelm", importance: 5 });
  });

  it("blocks on the name alone — everything else is optional", async () => {
    const region = await openCreateProject();
    expect(within(region).getByRole("button", { name: "Create" })).toBeDisabled();
    fireEvent.change(within(region).getByLabelText(/Name/), { target: { value: "Helm" } });
    expect(within(region).getByRole("button", { name: "Create" })).toBeEnabled();
  });

  it("reports the path the host actually created", async () => {
    const region = await openCreateProject({
      scaffoldProject: () =>
        Promise.resolve({ projectPath: "/Users/example/Projects/Helm", awaitingConfirmation: false })
    });
    fireEvent.change(within(region).getByLabelText(/Name/), { target: { value: "Helm" } });
    await act(async () => {
      fireEvent.click(within(region).getByRole("button", { name: "Create" }));
    });

    const status = document.querySelector(".action-status") as HTMLElement;
    await waitFor(() => expect(status).toHaveTextContent("/Users/example/Projects/Helm"));
  });
});

describe("check-scoreboard in the region", () => {
  async function openCheckScoreboard(overrides: Parameters<typeof renderShell>[0] = {}) {
    const { bridge } = renderShell(overrides);
    await act(async () => {
      await bridge.applyMode({ modeId: "entertainment" });
    });
    fireEvent.click(screen.getByRole("button", { name: "Check scoreboard" }));
    return screen.findByRole("region", { name: "Check scoreboard form" });
  }

  it("lists both leagues and caps the selection at three", async () => {
    const region = await openCheckScoreboard({
      listSportsEvents: () =>
        Promise.resolve({
          events: [1, 2, 3, 4].map((n) => ({
            id: `e${n}`,
            league: "nfl",
            name: `Game ${n}`,
            shortName: `G${n}`,
            state: "in" as const,
            detail: "Q1",
            competitors: [],
            leaderboard: []
          })),
          available: true,
          reason: null
        })
    });

    const games = await within(region).findByRole("group", { name: /Games/ });
    await waitFor(() => expect(within(games).getByLabelText(/G1/)).toBeInTheDocument());

    fireEvent.click(within(games).getByLabelText(/G1/));
    fireEvent.click(within(games).getByLabelText(/G2/));
    fireEvent.click(within(games).getByLabelText(/G3/));

    // At the cap the unchosen boxes disable rather than silently ignoring a click — and the
    // chosen ones stay live so unpicking is always possible.
    await waitFor(() => expect(within(games).getByLabelText(/G4/)).toBeDisabled());
    expect(within(games).getByLabelText(/G1/)).toBeEnabled();
  });

  it("opens the report with the chosen ids rather than writing anything", async () => {
    const region = await openCheckScoreboard();
    const games = await within(region).findByRole("group", { name: /Games/ });
    await waitFor(() => expect(within(games).getByLabelText(/CAR VS ARI/)).toBeInTheDocument());
    fireEvent.click(within(games).getByLabelText(/CAR VS ARI/));

    await act(async () => {
      fireEvent.click(within(region).getByRole("button", { name: "Show" }));
    });

    // The report is the result: it opens, and the status line only says what happened.
    const report = await screen.findByRole("region", { name: /Check scoreboard/ });
    expect(report).toBeInTheDocument();
    const status = document.querySelector(".action-status") as HTMLElement;
    await waitFor(() => expect(status).toHaveTextContent("Showing 1 game."));
  });

  it("says scores could not be read rather than showing an empty picker", async () => {
    // "Nothing is on today" and "we couldn't reach ESPN" are different facts.
    const region = await openCheckScoreboard({
      listSportsEvents: () =>
        Promise.resolve({ events: [], available: true, reason: "Couldn't reach nfl right now." })
    });
    await waitFor(() =>
      expect(within(region).getByText(/Couldn't reach nfl right now\./)).toBeInTheDocument()
    );
  });
});

describe("send-text in the region", () => {
  async function openSendText(overrides: Parameters<typeof renderShell>[0] = {}) {
    renderShell(overrides);
    // Executive slot 4.
    fireEvent.click(screen.getByRole("button", { name: "Send text" }));
    return screen.findByRole("region", { name: "Send text form" });
  }

  it("chooses nobody until a result is clicked — typing only filters", async () => {
    // For this form specifically, a half-typed name becoming a recipient is the difference
    // between a message and a mistake.
    const region = await openSendText();
    const search = within(region).getByRole("combobox");
    fireEvent.change(search, { target: { value: "jam" } });

    const match = await within(region).findByRole("option", { name: /Jamie Rivera/ });
    // Still nothing chosen, and the submit is still blocked.
    expect(within(region).getByRole("button", { name: "Send" })).toBeDisabled();

    fireEvent.click(match);
    await waitFor(() =>
      expect(within(region).getByText(/Jamie Rivera/)).toBeInTheDocument()
    );
  });

  it("says a group's size in the picker, because it changes what sending means", async () => {
    const region = await openSendText();
    fireEvent.change(within(region).getByRole("combobox"), { target: { value: "ski" } });
    expect(await within(region).findByRole("option", { name: /group of 6/ })).toBeInTheDocument();
  });

  it("reports 'confirm to send', never 'sent' — this action always gates", async () => {
    // The most consequential lie this surface could tell: nothing has left the machine until the
    // confirmation is approved.
    const sent: { target: string; targetKind: string; groupSize?: number }[] = [];
    const region = await openSendText({
      sendMessage: (input) => {
        sent.push(input);
        return Promise.resolve({
          targetName: "Ski trip",
          sent: false,
          awaitingConfirmation: true
        });
      }
    });

    fireEvent.change(within(region).getByRole("combobox"), { target: { value: "ski" } });
    fireEvent.click(await within(region).findByRole("option", { name: /Ski trip/ }));
    fireEvent.change(within(region).getByLabelText(/Message/), {
      target: { value: "  Running late.  " }
    });
    await act(async () => {
      fireEvent.click(within(region).getByRole("button", { name: "Send" }));
    });

    await waitFor(() => expect(sent).toHaveLength(1));
    // The group size travels so the confirmation can say how many people this reaches.
    expect(sent[0]).toMatchObject({ target: "chat123", targetKind: "chat", groupSize: 6 });

    const status = document.querySelector(".action-status") as HTMLElement;
    await waitFor(() => expect(status).toHaveTextContent("Confirm to send to Ski trip."));
    expect(status).not.toHaveTextContent(/^Sent/);
  });

  it("blocks on both the recipient and the message", async () => {
    const region = await openSendText();
    expect(within(region).getByRole("button", { name: "Send" })).toBeDisabled();
    fireEvent.change(within(region).getByLabelText(/Message/), { target: { value: "Hello" } });
    // A message with nobody to send it to is still blocked.
    expect(within(region).getByRole("button", { name: "Send" })).toBeDisabled();
  });
});

describe("Input field schema", () => {
  const form: InputForm = {
    actionId: "example",
    title: "Example",
    submitLabel: "Go",
    fields: [
      { name: "a", label: "A", kind: "text", required: true },
      { name: "b", label: "B", kind: "textarea", initialValue: "seeded" },
      {
        name: "r",
        endName: "rEnd",
        label: "R",
        kind: "datetimeRange",
        required: true,
        initialValue: "2026-08-03T14:00",
        initialEndValue: "2026-08-03T15:00"
      },
      { name: "d", label: "D", kind: "folderPicker" },
      // Every declared kind now renders, so the skip guard has no real example left. It exists
      // for the kind a FUTURE composer names, which is what this stands in for — cast in rather
      // than declared, because the type is deliberately closed.
      { name: "c", label: "C", kind: "someFutureKind" as InputField["kind"], required: true }
    ],
    submit: () => Promise.resolve({ message: "done" })
  };

  it("skips a field kind the renderer cannot draw rather than showing a broken control", () => {
    expect(renderableFields(form).map((field) => field.name)).toEqual(["a", "b", "r", "d"]);
  });

  it("seeds values from declared initial values", () => {
    // A range seeds BOTH halves under its own name and its `endName`.
    expect(initialValues(form)).toEqual({
      a: "",
      b: "seeded",
      r: "2026-08-03T14:00",
      rEnd: "2026-08-03T15:00",
      d: ""
    });
  });

  it("only blocks on required fields it can actually render", () => {
    const filled = { a: "x", b: "", r: "2026-08-03T14:00", rEnd: "2026-08-03T15:00", d: "" };
    // An unrendered required field must not deadlock the form — the user could never fill it in.
    expect(missingRequired(form, { ...filled, a: "" }).map((field) => field.name)).toEqual(["a"]);
    expect(missingRequired(form, filled)).toEqual([]);
    // Whitespace is not a value.
    expect(missingRequired(form, { ...filled, a: "   " }).map((field) => field.name)).toEqual(["a"]);
    // A range needs BOTH halves — a start with no end is not a filled-in range.
    expect(missingRequired(form, { ...filled, rEnd: "" }).map((field) => field.name)).toEqual(["r"]);
  });
});
