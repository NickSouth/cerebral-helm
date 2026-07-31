import type { CerebralBridge, CommandReceipt } from "../bridge/cerebralBridge";

/** The playback commands the Spotify widget can send (matches the `spotify.control` input enum). */
export type SpotifyControlAction = "play" | "pause" | "next" | "previous";

/**
 * Control the user's Spotify playback (NIC-133).
 *
 * Goes through the same command bus as every other action — `submitCommand` with the
 * `spotify <action>` grammar — so the `spotify.control` tool is planned by the runtime. Its risk is
 * honestly `external_write` (it hits Spotify's API), but the descriptor waives confirmation
 * (owner: play/pause/skip is too low-stakes to prompt), so it runs in one click. The returned
 * receipt only says whether the command was accepted.
 */
export function submitSpotifyControl(
  bridge: CerebralBridge,
  action: SpotifyControlAction
): Promise<CommandReceipt> {
  return bridge.submitCommand({ rawInput: `spotify ${action}`, source: "dashboard" });
}
