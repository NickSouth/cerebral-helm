import { describe, it, expect, vi } from "vitest";
import type { CerebralBridge, CommandReceipt, SubmitCommandInput } from "../bridge/cerebralBridge";
import { submitOpenProject } from "./openProject";

describe("submitOpenProject (NIC-131)", () => {
  it("submits the project grammar through the command bus and returns the receipt", async () => {
    const receipt: CommandReceipt = { commandId: "cmd_1", accepted: true };
    const submitCommand = vi.fn(async (_input: SubmitCommandInput) => receipt);
    const bridge = { submitCommand } as unknown as CerebralBridge;

    const result = await submitOpenProject(bridge, "/Users/x/Projects/cerebral-helm");

    expect(submitCommand).toHaveBeenCalledWith({
      rawInput: "project /Users/x/Projects/cerebral-helm",
      source: "dashboard"
    });
    expect(result).toBe(receipt);
  });

  it("preserves a path containing spaces verbatim (the parser takes the whole remainder)", async () => {
    const submitCommand = vi.fn(async (_input: SubmitCommandInput) => ({
      commandId: "cmd_2",
      accepted: true
    }));
    const bridge = { submitCommand } as unknown as CerebralBridge;

    await submitOpenProject(bridge, "/Users/x/My Projects/demo");

    expect(submitCommand).toHaveBeenCalledWith({
      rawInput: "project /Users/x/My Projects/demo",
      source: "dashboard"
    });
  });
});
