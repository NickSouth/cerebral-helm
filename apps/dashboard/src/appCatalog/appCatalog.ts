/**
 * Mock application catalog — the pre-Mac source of truth for the quick-app ids a mode
 * config may reference (quickApps[]) and the "More Apps" list (design spec §5.6,
 * NIC-117 i). On the Mac target this is replaced by real application discovery (which also
 * supplies the real OS app icons); pre-Mac it is a fixed catalog so a dangling quick-app
 * reference is a build failure (scripts/validate-config.mjs). Catalog membership is
 * reference resolution (typo protection); runtime "installed / available" is a separate,
 * gracefully-degraded concern (an unavailable app stays editable, §5.6).
 *
 * `category` drives the pre-Mac placeholder icon (a generic monochrome category glyph,
 * owner decision) — never a bundled brand logo. Kept in lockstep with appCatalog.manifest.json
 * (the Node-readable mirror the gate reads) by appCatalog.test.ts.
 */

export type AppCategory =
  | "browser"
  | "mail"
  | "files"
  | "assistant"
  | "code"
  | "terminal"
  | "tasks"
  | "learning"
  | "music"
  | "video"
  | "games"
  | "chat"
  | "photos";

export interface AppDefinition {
  readonly id: string;
  readonly label: string;
  readonly category: AppCategory;
}

export const APP_CATALOG = [
  { id: "chrome", label: "Chrome", category: "browser" },
  { id: "gmail", label: "Gmail", category: "mail" },
  { id: "finder", label: "Finder", category: "files" },
  { id: "claude-desktop", label: "Claude Desktop", category: "assistant" },
  { id: "vscode", label: "VS Code", category: "code" },
  { id: "terminal", label: "Terminal", category: "terminal" },
  { id: "github", label: "GitHub", category: "code" },
  { id: "docker", label: "Docker", category: "code" },
  { id: "linear", label: "Linear", category: "tasks" },
  { id: "canvas", label: "Canvas", category: "learning" },
  { id: "drive", label: "Google Drive", category: "files" },
  { id: "quizlet", label: "Quizlet", category: "learning" },
  { id: "spotify", label: "Spotify", category: "music" },
  { id: "youtube", label: "YouTube", category: "video" },
  { id: "steam", label: "Steam", category: "games" },
  { id: "discord", label: "Discord", category: "chat" },
  { id: "photos", label: "Photos", category: "photos" }
] as const satisfies readonly AppDefinition[];

export type AppId = (typeof APP_CATALOG)[number]["id"];

/** The registered application ids, in catalog order (mirrored by appCatalog.manifest.json). */
export const APP_IDS: readonly AppId[] = APP_CATALOG.map((app) => app.id);

const APP_BY_ID: ReadonlyMap<string, AppDefinition> = new Map(APP_CATALOG.map((app) => [app.id, app]));

export function isRegisteredAppId(id: string): id is AppId {
  return APP_BY_ID.has(id);
}

/** Resolve an app id to its catalog entry (label + category), or undefined if unknown. */
export function appDefinition(id: string): AppDefinition | undefined {
  return APP_BY_ID.get(id);
}
