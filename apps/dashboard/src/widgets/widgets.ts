/**
 * Widget registry — the source of truth for the eight dashboard widget slots
 * (design spec §5.3 / §5.11, UI-CONSTITUTION §6). A mode config's `widgets.left` /
 * `widgets.right` must reference one of these ids; the build gate
 * (scripts/validate-config.mjs) fails on a dangling reference. The rail slot maps a
 * widget id to its component from this registry — never a per-mode conditional.
 *
 * Kept in lockstep with widgets.manifest.json (the Node-readable mirror the gate
 * reads) by widgets.test.ts — the same idiom as the design-token manifest.
 */

export type WidgetSide = "left" | "right";

export interface WidgetDefinition {
  readonly id: string;
  readonly label: string;
  /** The rail slot(s) this widget is designed for (design spec §5.3 / §5.11). */
  readonly sides: readonly WidgetSide[];
  /** One line describing the data the widget surfaces. */
  readonly summary: string;
}

export const WIDGET_REGISTRY = [
  { id: "market-brief", label: "Market Brief", sides: ["left"], summary: "Tracked stocks and their movement." },
  { id: "project-git-status", label: "Project Git Status", sides: ["left"], summary: "Build, test, branch, PR, and deploy summary." },
  { id: "deadlines", label: "Deadlines", sides: ["left"], summary: "Upcoming assignments and due dates." },
  { id: "spotify", label: "Spotify", sides: ["left"], summary: "Current and recent listening." },
  { id: "projects", label: "Projects", sides: ["right"], summary: "Pinned and active projects with status." },
  { id: "repositories", label: "Repositories", sides: ["right"], summary: "Repositories with branch and worktree state." },
  { id: "courses", label: "Courses", sides: ["right"], summary: "Current courses and their concise state." },
  { id: "media-list", label: "Media List", sides: ["right"], summary: "Continue, queued, saved, and recent media." }
] as const satisfies readonly WidgetDefinition[];

export type WidgetId = (typeof WIDGET_REGISTRY)[number]["id"];

/** The registered widget ids, in registry order (mirrored by widgets.manifest.json). */
export const WIDGET_IDS: readonly WidgetId[] = WIDGET_REGISTRY.map((widget) => widget.id);

export function isRegisteredWidgetId(id: string): id is WidgetId {
  return (WIDGET_IDS as readonly string[]).includes(id);
}
