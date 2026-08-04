import type { CerebralBridge } from "../bridge/cerebralBridge";
import type { InputForm, InputValues } from "./inputForm";

/**
 * `create-playlist` — an empty, named playlist in the connected Spotify account (quick actions
 * phase 4).
 *
 * **Empty on purpose.** Seeding it with tracks means searching Spotify's catalogue and choosing
 * from the results, which is a picker with its own surface, not a field on this form. Creating the
 * playlist is the part that needed the API; filling it is something Spotify itself is good at.
 *
 * **Private by default.** Spotify's API defaults `public` to `true`, so omitting the field would
 * publish to the user's profile because nobody said otherwise. The form asks, and the confirmation
 * discloses the answer in words.
 *
 * **This is the action that disturbs a working integration.** The playlist scopes were added to the
 * OAuth request alongside it, so a grant made before then still drives the now-playing widget and
 * the playback controls, and is refused here. That comes back as its own error, and the form says
 * to reconnect rather than implying the account is broken.
 */

/** The visibility choice. Values are the strings the select holds; `isPublic` derives from them. */
export const PLAYLIST_VISIBILITY = [
  { value: "private", label: "Private" },
  { value: "public", label: "Public" }
] as const;

/** Whether the chosen visibility means public. Anything unrecognized is private — the safe read. */
export function isPublicVisibility(value: string | undefined): boolean {
  return (value ?? "").trim() === "public";
}

/** Whether a failed submit was the scope gap, which the user can fix by reconnecting. */
export function isReconnectError(error: unknown): boolean {
  const code = (error as { code?: unknown } | null)?.code;
  const message = error instanceof Error ? error.message : String(error ?? "");
  return code === "spotify_reconnect_required" || message.includes("spotify_reconnect_required");
}

export function createPlaylistForm(bridge: CerebralBridge): InputForm {
  return {
    actionId: "create-playlist",
    title: "Create playlist",
    submitLabel: "Create",
    fields: [
      {
        name: "name",
        label: "Name",
        kind: "text",
        required: true,
        placeholder: "What's it for?"
      },
      {
        name: "visibility",
        label: "Visibility",
        kind: "select",
        source: { kind: "static", options: [...PLAYLIST_VISIBILITY] },
        initialValue: "private",
        hint: "Public playlists appear on your Spotify profile."
      },
      { name: "description", label: "Description", kind: "textarea", placeholder: "Optional" }
    ],
    async submit(values: InputValues) {
      const name = values.name.trim();
      try {
        const result = await bridge.createSpotifyPlaylist({
          name,
          description: values.description?.trim() || undefined,
          isPublic: isPublicVisibility(values.visibility)
        });

        // Never report "created" for something still waiting on the user's approval.
        if (result.awaitingConfirmation) {
          return { message: `“${name}” needs your confirmation before it's created.` };
        }
        return { message: `Created the playlist “${result.name}”.` };
      } catch (error) {
        // The one failure with a one-step remedy gets to say what it is; everything else falls
        // through to the region's generic handling with the form and its typing intact.
        if (isReconnectError(error)) {
          return {
            message: "Spotify needs reconnecting before it can make playlists — Settings → Setup.",
            failed: true
          };
        }
        throw error;
      }
    }
  };
}
