import type { HeimlichState } from "../bridge/types";

/**
 * Integration boundary for the Heimlich ribbon (NIC-60). The ribbon is an **external WebGL motion
 * asset** (a Unicorn Studio scene), not a hand-built shader — this module is the seam that the
 * dashboard binds to. Adding real per-state scenes later means only editing `RIBBON_SCENES`; no
 * component changes.
 */
export type HeimlichRibbonState = "idle" | "listening" | "thinking" | "speaking" | "focus";

export interface RibbonScene {
  /**
   * Unicorn Studio project id for this state. `null` until the real asset exists — the embed then
   * renders the static gradient fallback instead of loading the vendor script.
   */
  readonly projectId: string | null;
  /** Optional scene parameters passed through to the embed when per-state tuning lands. */
  readonly params?: Readonly<Record<string, string | number>>;
}

/** Vendor embed script. Pinned; only loaded when a scene has a real `projectId`. */
export const UNICORN_SCRIPT_SRC = "https://cdn.unicorn.studio/v1.4.0/unicornStudio.umd.js";

// All states share one placeholder for now (no asset yet → fallback). Swap in distinct scene ids
// per state later without touching the component.
const PLACEHOLDER: RibbonScene = { projectId: null };

export const RIBBON_SCENES: Record<HeimlichRibbonState, RibbonScene> = {
  idle: PLACEHOLDER,
  listening: PLACEHOLDER,
  thinking: PLACEHOLDER,
  speaking: PLACEHOLDER,
  focus: PLACEHOLDER,
};

export function sceneForState(state: HeimlichRibbonState): RibbonScene {
  return RIBBON_SCENES[state] ?? PLACEHOLDER;
}

/** Collapse the dashboard's runtime `HeimlichState` onto the ribbon's five presentation states. */
export function toRibbonState(state: HeimlichState): HeimlichRibbonState {
  switch (state) {
    case "listening":
      return "listening";
    case "thinking":
      return "thinking";
    case "success":
      return "speaking";
    case "acting":
    case "awaiting_confirmation":
    case "error":
      return "focus";
    case "idle":
    case "offline":
    default:
      return "idle";
  }
}
