/**
 * Mock application catalog — the pre-Mac source of truth for the quick-app ids a mode
 * config may reference (quickApps[]) and the "More Apps" list (design spec §5.6,
 * NIC-117 i). On the Mac target this is replaced by real application discovery; pre-Mac
 * it is a fixed catalog so a dangling quick-app reference is a build failure
 * (scripts/validate-config.mjs). Catalog membership is reference resolution (typo
 * protection); runtime "installed / available" is a separate, gracefully-degraded
 * concern (an unavailable app stays editable, §5.6).
 *
 * Kept in lockstep with appCatalog.manifest.json (the Node-readable mirror the gate
 * reads) by appCatalog.test.ts — the same idiom as the design-token manifest.
 */

export interface AppDefinition {
  readonly id: string;
  readonly label: string;
}

export const APP_CATALOG = [
  { id: "chrome", label: "Chrome" },
  { id: "gmail", label: "Gmail" },
  { id: "finder", label: "Finder" },
  { id: "claude-desktop", label: "Claude Desktop" },
  { id: "vscode", label: "VS Code" },
  { id: "terminal", label: "Terminal" },
  { id: "github", label: "GitHub" },
  { id: "docker", label: "Docker" },
  { id: "linear", label: "Linear" },
  { id: "canvas", label: "Canvas" },
  { id: "drive", label: "Google Drive" },
  { id: "quizlet", label: "Quizlet" },
  { id: "spotify", label: "Spotify" },
  { id: "youtube", label: "YouTube" },
  { id: "steam", label: "Steam" },
  { id: "discord", label: "Discord" },
  { id: "photos", label: "Photos" }
] as const satisfies readonly AppDefinition[];

export type AppId = (typeof APP_CATALOG)[number]["id"];

/** The registered application ids, in catalog order (mirrored by appCatalog.manifest.json). */
export const APP_IDS: readonly AppId[] = APP_CATALOG.map((app) => app.id);

export function isRegisteredAppId(id: string): id is AppId {
  return (APP_IDS as readonly string[]).includes(id);
}
