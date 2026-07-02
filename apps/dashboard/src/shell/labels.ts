import type { AgentSummary, HeimlichState } from "../bridge/types";

const HEIMLICH_STATE_LABELS: Readonly<Record<HeimlichState, string>> = {
  idle: "Idle",
  listening: "Listening",
  thinking: "Thinking",
  acting: "Working",
  awaiting_confirmation: "Awaiting confirmation",
  success: "Done",
  error: "Error",
  offline: "Offline"
};

const AGENT_ACTIVITY_LABELS: Readonly<Record<AgentSummary["activity"], string>> = {
  idle: "Idle",
  waiting: "Waiting",
  thinking: "Thinking",
  ready: "Ready"
};

/** Heimlich's status as text — the primary status carrier, never color/motion alone (§5.8). */
export function heimlichStateLabel(state: HeimlichState): string {
  return HEIMLICH_STATE_LABELS[state];
}

/** An agent's runtime status as text (design spec §5.10), paired with a non-color cue. */
export function agentActivityLabel(activity: AgentSummary["activity"]): string {
  return AGENT_ACTIVITY_LABELS[activity];
}

/** Turn a config id like `open-developer-layout` into a display label `Open developer layout`. */
export function humanizeId(id: string): string {
  const text = id.replace(/[-_]/g, " ").trim();
  return text.length > 0 ? text.charAt(0).toUpperCase() + text.slice(1) : id;
}
