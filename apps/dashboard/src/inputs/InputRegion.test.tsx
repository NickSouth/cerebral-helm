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
  type InputForm
} from "./inputForm";

/** The Input region and its field schema (docs/quick-actions/PLAN.md phase 3). */

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
      // Declared but not yet rendered — they arrive with the actions that need them.
      { name: "c", label: "C", kind: "combobox", required: true },
      { name: "d", label: "D", kind: "folderPicker" }
    ],
    submit: () => Promise.resolve({ message: "done" })
  };

  it("skips a field kind the renderer cannot draw rather than showing a broken control", () => {
    expect(renderableFields(form).map((field) => field.name)).toEqual(["a", "b", "r"]);
  });

  it("seeds values from declared initial values", () => {
    // A range seeds BOTH halves under its own name and its `endName`.
    expect(initialValues(form)).toEqual({
      a: "",
      b: "seeded",
      r: "2026-08-03T14:00",
      rEnd: "2026-08-03T15:00"
    });
  });

  it("only blocks on required fields it can actually render", () => {
    const filled = { a: "x", b: "", r: "2026-08-03T14:00", rEnd: "2026-08-03T15:00" };
    // An unrendered required field must not deadlock the form — the user could never fill it in.
    expect(missingRequired(form, { ...filled, a: "" }).map((field) => field.name)).toEqual(["a"]);
    expect(missingRequired(form, filled)).toEqual([]);
    // Whitespace is not a value.
    expect(missingRequired(form, { ...filled, a: "   " }).map((field) => field.name)).toEqual(["a"]);
    // A range needs BOTH halves — a start with no end is not a filled-in range.
    expect(missingRequired(form, { ...filled, rEnd: "" }).map((field) => field.name)).toEqual(["r"]);
  });
});
