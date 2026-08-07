import { describe, it, expect, vi } from "vitest";
import type { CerebralBridge, CommandReceipt, SubmitCommandInput } from "../bridge/cerebralBridge";
import { submitWebOpen } from "./webOpen";

describe("submitWebOpen (NIC-127)", () => {
  it("submits the web grammar through the command bus and returns the receipt", async () => {
    const receipt: CommandReceipt = { commandId: "cmd_1", accepted: true };
    const submitCommand = vi.fn(async (_input: SubmitCommandInput) => receipt);
    const bridge = { submitCommand } as unknown as CerebralBridge;

    const result = await submitWebOpen(bridge, "https://example.com/article");

    expect(submitCommand).toHaveBeenCalledWith({
      rawInput: "web https://example.com/article",
      source: "dashboard"
    });
    expect(result).toBe(receipt);
  });

  it("passes the url verbatim, including query params (the parser takes the whole remainder)", async () => {
    const submitCommand = vi.fn(async (_input: SubmitCommandInput) => ({
      commandId: "cmd_2",
      accepted: true
    }));
    const bridge = { submitCommand } as unknown as CerebralBridge;

    await submitWebOpen(bridge, "https://news.example.com/story?id=42&ref=home");

    expect(submitCommand).toHaveBeenCalledWith({
      rawInput: "web https://news.example.com/story?id=42&ref=home",
      source: "dashboard"
    });
  });
});
