import { render, screen, fireEvent, waitFor, act } from "@testing-library/react";
import { CommandSurface } from "./CommandSurface";
import type { SuggestedCommand } from "../bridge/cerebralBridge";

/** NIC-168: the shared launcher/palette input with bridge-ranked suggestions. */

const chrome: SuggestedCommand = {
  command: "open chrome",
  label: "Google Chrome",
  kind: "app",
  requiresArgument: false,
  available: true
};

const unavailableApp: SuggestedCommand = {
  command: "open xcode",
  label: "Xcode",
  kind: "app",
  requiresArgument: false,
  available: false,
  unavailableReason: "Opening applications is not available yet."
};

const noteTemplate: SuggestedCommand = {
  command: "note ",
  label: "Capture a note",
  detail: "note <text>",
  kind: "pattern",
  requiresArgument: true,
  available: true
};

function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

function renderSurface(
  fetchSuggestions: (query: string) => Promise<readonly SuggestedCommand[]>,
  overrides: Partial<Parameters<typeof CommandSurface>[0]> = {}
) {
  const onSubmit = vi.fn();
  render(
    <CommandSurface
      variant="launcher"
      placeholder="Type a command…"
      ariaLabel="Test launcher"
      onSubmit={onSubmit}
      fetchSuggestions={fetchSuggestions}
      {...overrides}
    />
  );
  return { onSubmit, input: screen.getByLabelText("Test launcher") };
}

/** Real-timers pause longer than the debounce, for asserting something did NOT happen. */
function afterDebounce(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 180));
}

describe("CommandSurface suggestions (NIC-168)", () => {
  it("fetches ranked suggestions after the debounce and renders label, command, and kind", async () => {
    const fetchSuggestions = vi.fn().mockResolvedValue([chrome]);
    const { input } = renderSurface(fetchSuggestions);

    fireEvent.change(input, { target: { value: "chr" } });

    const row = await screen.findByRole("option", { name: /Google Chrome/ });
    expect(row).toBeEnabled();
    expect(row).toHaveTextContent("open chrome");
    expect(row).toHaveTextContent("app");
    expect(fetchSuggestions).toHaveBeenCalledWith("chr");
  });

  it("applies only the latest query's results — a slow early response never wins", async () => {
    const first = deferred<readonly SuggestedCommand[]>();
    const second = deferred<readonly SuggestedCommand[]>();
    const fetchSuggestions = vi.fn((query: string) =>
      query === "a" ? first.promise : second.promise
    );
    const { input } = renderSurface(fetchSuggestions);

    fireEvent.change(input, { target: { value: "a" } });
    await waitFor(() => expect(fetchSuggestions).toHaveBeenCalledWith("a"));
    fireEvent.change(input, { target: { value: "ab" } });
    await waitFor(() => expect(fetchSuggestions).toHaveBeenCalledWith("ab"));

    // The newer request resolves first; the stale one lands afterwards.
    second.resolve([chrome]);
    await screen.findByRole("option", { name: /Google Chrome/ });
    await act(async () => {
      first.resolve([noteTemplate]);
    });

    expect(screen.queryByRole("option", { name: /Capture a note/ })).toBeNull();
    expect(screen.getByRole("option", { name: /Google Chrome/ })).toBeInTheDocument();
  });

  it("selects the best runnable row by default (skipping unavailable) and Enter executes it", async () => {
    const fetchSuggestions = vi.fn().mockResolvedValue([unavailableApp, chrome]);
    const { onSubmit, input } = renderSurface(fetchSuggestions);

    fireEvent.change(input, { target: { value: "o" } });
    const selected = await screen.findByRole("option", { name: /Google Chrome/ });

    // Spotlight semantics (NIC-168): no arrow key needed — the best guess is pre-selected.
    expect(selected).toHaveAttribute("aria-selected", "true");
    expect(input).toHaveAttribute("aria-activedescendant", selected.id);
    expect(screen.getByRole("option", { name: /Xcode/ })).toHaveAttribute("aria-selected", "false");

    fireEvent.keyDown(input, { key: "Enter" });
    expect(onSubmit).toHaveBeenCalledWith("open chrome");
  });

  it("Escape first clears the selection (Enter then submits verbatim), Escape again closes", async () => {
    const fetchSuggestions = vi.fn().mockResolvedValue([chrome]);
    const { onSubmit, input } = renderSurface(fetchSuggestions);
    const windowEscapes = vi.fn();
    window.addEventListener("keydown", windowEscapes);

    fireEvent.change(input, { target: { value: "chr" } });
    await screen.findByRole("option", { name: /Google Chrome/ });

    // Stage one: clears the selection and swallows the event (the palette's
    // window-level Escape must not dismiss yet).
    fireEvent.keyDown(input, { key: "Escape" });
    expect(windowEscapes).not.toHaveBeenCalled();
    expect(screen.getByRole("option", { name: /Google Chrome/ })).toHaveAttribute(
      "aria-selected",
      "false"
    );

    fireEvent.keyDown(input, { key: "Enter" });
    expect(onSubmit).toHaveBeenCalledWith("chr");

    // Stage two (selection already clear): propagates and closes the list.
    fireEvent.change(input, { target: { value: "chr" } });
    fireEvent.keyDown(input, { key: "Escape" });
    fireEvent.keyDown(input, { key: "Escape" });
    expect(windowEscapes).toHaveBeenCalled();
    window.removeEventListener("keydown", windowEscapes);
  });

  it("ghost-fills the selected command's remainder; Tab accepts it without executing", async () => {
    const fetchSuggestions = vi.fn().mockResolvedValue([chrome]);
    const { onSubmit, input } = renderSurface(fetchSuggestions);

    fireEvent.change(input, { target: { value: "open ch" } });
    await screen.findByRole("option", { name: /Google Chrome/ });

    expect(screen.getByTestId("command-ghost")).toHaveTextContent("open chrome");

    fireEvent.keyDown(input, { key: "Tab" });
    expect(input).toHaveValue("open chrome");
    expect(onSubmit).not.toHaveBeenCalled();
  });

  it("ArrowRight at the end of the input accepts the ghost completion", async () => {
    const fetchSuggestions = vi.fn().mockResolvedValue([chrome]);
    const { input } = renderSurface(fetchSuggestions);

    fireEvent.change(input, { target: { value: "open ch" } });
    await screen.findByRole("option", { name: /Google Chrome/ });

    (input as HTMLInputElement).setSelectionRange(7, 7);
    fireEvent.keyDown(input, { key: "ArrowRight" });
    expect(input).toHaveValue("open chrome");
  });

  it("shows no ghost when the selected command does not extend the typed text", async () => {
    const fetchSuggestions = vi.fn().mockResolvedValue([chrome]);
    const { input } = renderSurface(fetchSuggestions);

    // A typo match ("chrme" → "open chrome") cannot be a caret continuation.
    fireEvent.change(input, { target: { value: "chrme" } });
    await screen.findByRole("option", { name: /Google Chrome/ });

    expect(screen.queryByTestId("command-ghost")).toBeNull();
  });

  it("a template row fills the input with its command prefix instead of executing", async () => {
    const fetchSuggestions = vi.fn().mockResolvedValue([noteTemplate]);
    const { onSubmit, input } = renderSurface(fetchSuggestions);

    fireEvent.change(input, { target: { value: "no" } });
    await screen.findByRole("option", { name: /Capture a note/ });

    fireEvent.keyDown(input, { key: "ArrowDown" });
    fireEvent.keyDown(input, { key: "Enter" });

    expect(onSubmit).not.toHaveBeenCalled();
    expect(input).toHaveValue("note ");
  });

  it("clicking a runnable row executes its command", async () => {
    const fetchSuggestions = vi.fn().mockResolvedValue([chrome]);
    const { onSubmit, input } = renderSurface(fetchSuggestions);

    fireEvent.change(input, { target: { value: "chr" } });
    const row = await screen.findByRole("option", { name: /Google Chrome/ });
    fireEvent.mouseDown(row);

    expect(onSubmit).toHaveBeenCalledWith("open chrome");
  });

  it("a failed fetch degrades to the bare input; typed submissions keep working", async () => {
    const fetchSuggestions = vi.fn().mockRejectedValue(new Error("bridge down"));
    const { onSubmit, input } = renderSurface(fetchSuggestions);

    fireEvent.change(input, { target: { value: "chr" } });
    await afterDebounce();

    expect(screen.queryByRole("listbox")).toBeNull();
    fireEvent.keyDown(input, { key: "Enter" });
    expect(onSubmit).toHaveBeenCalledWith("chr");
  });

  it("spotlight mode fetches nothing until the user types (NIC-77)", async () => {
    const fetchSuggestions = vi.fn().mockResolvedValue([chrome]);
    const { input } = renderSurface(fetchSuggestions, { spotlight: true });

    fireEvent.focus(input);
    await afterDebounce();
    expect(fetchSuggestions).not.toHaveBeenCalled();

    fireEvent.change(input, { target: { value: "chr" } });
    await screen.findByRole("option", { name: /Google Chrome/ });
    expect(fetchSuggestions).toHaveBeenCalledWith("chr");
  });
});
