import { describe, it, expect, vi } from "vitest";
import type { CerebralBridge, CommandReceipt, SubmitCommandInput } from "../bridge/cerebralBridge";
import { submitSpotifyControl } from "./spotifyControl";

describe("submitSpotifyControl (NIC-133)", () => {
  it("submits the spotify grammar for each action through the command bus", async () => {
    const receipt: CommandReceipt = { commandId: "cmd_1", accepted: true };
    const submitCommand = vi.fn(async (_input: SubmitCommandInput) => receipt);
    const bridge = { submitCommand } as unknown as CerebralBridge;

    for (const action of ["play", "pause", "next", "previous"] as const) {
      const result = await submitSpotifyControl(bridge, action);
      expect(submitCommand).toHaveBeenCalledWith({ rawInput: `spotify ${action}`, source: "dashboard" });
      expect(result).toBe(receipt);
    }
  });
});
