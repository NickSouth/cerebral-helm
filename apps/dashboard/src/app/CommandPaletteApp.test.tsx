import { render, screen, fireEvent } from "@testing-library/react";
import { CommandPaletteApp } from "./CommandPaletteApp";

interface PaletteControlWindow {
  webkit?: { messageHandlers?: { paletteControl?: { postMessage: (m: unknown) => void } } };
}

function installPaletteControl(): ReturnType<typeof vi.fn> {
  const postMessage = vi.fn();
  (window as unknown as PaletteControlWindow).webkit = {
    messageHandlers: { paletteControl: { postMessage } }
  };
  return postMessage;
}

afterEach(() => {
  delete (window as unknown as PaletteControlWindow).webkit;
});

describe("CommandPaletteApp (NIC-75 floating palette route)", () => {
  it("renders only the command input, not the full dashboard shell", () => {
    render(<CommandPaletteApp />);
    expect(screen.getByLabelText("Command palette")).toBeInTheDocument();
    // The full dashboard chrome (brand, mode rail, panels) must not render in the palette.
    expect(screen.queryByRole("img", { name: "CerebralHelm" })).toBeNull();
  });

  it("asks the native shell to dismiss after submitting a command", () => {
    const postMessage = installPaletteControl();
    render(<CommandPaletteApp />);
    const input = screen.getByLabelText("Command palette");
    fireEvent.change(input, { target: { value: "note buy milk" } });
    fireEvent.keyDown(input, { key: "Enter" });
    expect(postMessage).toHaveBeenCalledWith({ action: "dismiss" });
  });

  it("dismisses on Escape", () => {
    const postMessage = installPaletteControl();
    render(<CommandPaletteApp />);
    fireEvent.keyDown(window, { key: "Escape" });
    expect(postMessage).toHaveBeenCalledWith({ action: "dismiss" });
  });

  it("exposes __cerebralFocusPalette so the native summon can focus the input", () => {
    render(<CommandPaletteApp />);
    const focus = (window as unknown as { __cerebralFocusPalette?: () => void })
      .__cerebralFocusPalette;
    expect(typeof focus).toBe("function");
    focus?.();
    expect(document.querySelector(".command-palette input")).toBe(document.activeElement);
  });
});
