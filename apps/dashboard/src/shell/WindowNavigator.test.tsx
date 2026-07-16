import { render, screen, fireEvent, waitFor, within } from "@testing-library/react";
import { vi } from "vitest";
import { WindowNavigator } from "./WindowNavigator";
import { BridgeProvider } from "../state/BridgeProvider";
import { createMockCerebralBridge } from "../bridge/mockCerebralBridge";

function renderNavigator(onClose = vi.fn()) {
  const bridge = createMockCerebralBridge();
  render(
    <BridgeProvider bridge={bridge}>
      <WindowNavigator variant="overlay" onClose={onClose} />
    </BridgeProvider>
  );
  return { bridge, onClose };
}

describe("WindowNavigator (NIC-143)", () => {
  it("lists open windows grouped by app, collapsing multi-window apps to a stack", async () => {
    renderNavigator();
    // The single-window app shows its window; the multi-window app (Chrome) collapses to
    // its front window plus a count badge.
    expect(await screen.findByText("BridgeSession.swift — cerebral-helm")).toBeInTheDocument();
    expect(screen.getByText("Inbox — Gmail")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Show all 2 Google Chrome windows/ })).toBeInTheDocument();
    // The second Chrome window is hidden until the stack is expanded.
    expect(screen.queryByText("CerebralHelm · GitHub")).toBeNull();
  });

  it("expands a stacked app to reveal every window", async () => {
    renderNavigator();
    fireEvent.click(await screen.findByRole("button", { name: /Show all 2 Google Chrome windows/ }));
    expect(screen.getByText("CerebralHelm · GitHub")).toBeInTheDocument();
  });

  it("minimizes a window through the bridge and refreshes", async () => {
    const { bridge } = renderNavigator();
    const minimize = vi.spyOn(bridge, "minimizeWindow");
    const list = vi.spyOn(bridge, "listWindows");
    await screen.findByText("BridgeSession.swift — cerebral-helm");
    fireEvent.click(screen.getByRole("button", { name: "Minimize BridgeSession.swift — cerebral-helm" }));
    await waitFor(() => expect(minimize).toHaveBeenCalledWith({ windowId: "2001" }));
    // The list is re-read after the action so the tiles reflect the new state.
    await waitFor(() => expect(list).toHaveBeenCalled());
  });

  it("closing a window routes to the bridge", async () => {
    const { bridge } = renderNavigator();
    const close = vi.spyOn(bridge, "closeWindow");
    await screen.findByText("BridgeSession.swift — cerebral-helm");
    fireEvent.click(screen.getByRole("button", { name: "Close BridgeSession.swift — cerebral-helm" }));
    await waitFor(() => expect(close).toHaveBeenCalledWith({ windowId: "2001" }));
  });

  it("clicking a window surfaces it and dismisses the navigator", async () => {
    const { bridge, onClose } = renderNavigator();
    const surface = vi.spyOn(bridge, "surfaceWindow");
    const dialog = await screen.findByRole("dialog", { name: "Open windows" });
    fireEvent.click(within(dialog).getByRole("button", { name: "Surface BridgeSession.swift — cerebral-helm" }));
    await waitFor(() => expect(surface).toHaveBeenCalledWith({ windowId: "2001" }));
    await waitFor(() => expect(onClose).toHaveBeenCalled());
  });
});
