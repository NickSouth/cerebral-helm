import { describe, it, expect, vi } from "vitest";
import type { CerebralBridge, CommandReceipt, SubmitCommandInput } from "../bridge/cerebralBridge";
import { submitGoogleSearch } from "./googleSearch";

describe("submitGoogleSearch (NIC-134)", () => {
  it("submits the google grammar through the command bus and returns the receipt", async () => {
    const receipt: CommandReceipt = { commandId: "cmd_1", accepted: true };
    const submitCommand = vi.fn(async (_input: SubmitCommandInput) => receipt);
    const bridge = { submitCommand } as unknown as CerebralBridge;

    const result = await submitGoogleSearch(bridge, "where to watch The Bear");

    expect(submitCommand).toHaveBeenCalledWith({
      rawInput: "google where to watch The Bear",
      source: "dashboard"
    });
    expect(result).toBe(receipt);
  });

  it("passes a query with spaces and punctuation verbatim (the parser takes the whole remainder)", async () => {
    const submitCommand = vi.fn(async (_input: SubmitCommandInput) => ({
      commandId: "cmd_2",
      accepted: true
    }));
    const bridge = { submitCommand } as unknown as CerebralBridge;

    await submitGoogleSearch(bridge, "where to watch Dune: Part Two");

    expect(submitCommand).toHaveBeenCalledWith({
      rawInput: "google where to watch Dune: Part Two",
      source: "dashboard"
    });
  });
});
