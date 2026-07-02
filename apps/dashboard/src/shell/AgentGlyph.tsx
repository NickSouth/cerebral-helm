import type { ReactNode } from "react";

/**
 * Agent identity glyphs for the R2 roster (design spec §5.10): a fixed icon per agent id, shown
 * inside the agent's circular avatar. Identity is fixed per id and never changes by mode
 * (constitution §6); the line icons inherit color from the avatar via `currentColor`. Same
 * construction as {@link AppGlyph}. NIC-118 supplies the final identity assets.
 */
const GLYPHS: Readonly<Record<string, ReactNode>> = {
  // Magnifying glass — Research Analyst.
  "research-analyst": (
    <>
      <circle cx="11" cy="11" r="6" />
      <path d="M20 20l-4.3-4.3" />
    </>
  ),
  // Dollar in a coin — Financial Advisor.
  "financial-advisor": (
    <>
      <circle cx="12" cy="12" r="8.2" />
      <path d="M12 7v10" />
      <path d="M14.6 9.1c-.6-.8-1.6-1.2-2.7-1.2-1.4 0-2.6.8-2.6 1.9s1.2 1.7 2.6 1.7 2.6.8 2.6 1.9-1.2 1.9-2.6 1.9c-1.1 0-2.1-.4-2.7-1.2" />
    </>
  ),
  // Clipboard with checks — Project Manager.
  "project-manager": (
    <>
      <rect x="5" y="4.5" width="14" height="16.5" rx="2" />
      <path d="M9 4.5a3 3 0 0 1 6 0" />
      <path d="M8.5 11l1.4 1.4 2.6-2.6M8.5 16l1.4 1.4 2.6-2.6" />
    </>
  ),
  // Gear — System Janitor.
  "system-janitor": (
    <>
      <circle cx="12" cy="12" r="3" />
      <path d="M12 2.5v2.4M12 19.1v2.4M4.2 7l2 1.2M17.8 15.8l2 1.2M4.2 17l2-1.2M17.8 8.2l2-1.2" />
    </>
  )
};

export function AgentGlyph({ agentId }: { agentId: string }) {
  return (
    <svg
      className="agent-glyph"
      viewBox="0 0 24 24"
      width="18"
      height="18"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      {GLYPHS[agentId] ?? GLYPHS["research-analyst"]}
    </svg>
  );
}
