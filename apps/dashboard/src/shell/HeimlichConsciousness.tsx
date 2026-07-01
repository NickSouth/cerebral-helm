import { useEffect, useRef, useState } from "react";
import { useDashboardState } from "../state/DashboardStateProvider";
import type { HeimlichState } from "../bridge/types";
import Threads from "./Threads";

interface HeimlichConsciousnessProps {
  /** Allow the field to receive pointer events. Decorative by default — never steals clicks. */
  readonly interactive?: boolean;
}

type RibbonState = "idle" | "listening" | "thinking" | "speaking" | "focus";
type Rgb = [number, number, number];

/** Collapse the dashboard's 8 runtime states onto the 5 presentation states of the stream. */
function toRibbonState(state: HeimlichState): RibbonState {
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
    default:
      return "idle";
  }
}

/** Per-state flow character (Threads props). Provisional — tune once the base look is approved. */
const PARAMS: Record<RibbonState, { amplitude: number; distance: number; speed: number }> = {
  idle: { amplitude: 1.0, distance: 0, speed: 0.85 },
  listening: { amplitude: 1.2, distance: 0.1, speed: 1.3 },
  thinking: { amplitude: 1.6, distance: 0.2, speed: 1.8 },
  speaking: { amplitude: 1.4, distance: 0.15, speed: 1.5 },
  focus: { amplitude: 0.9, distance: 0.05, speed: 0.8 },
};

const DEFAULT_GOLD: Rgb = [0.89, 0.647, 0.192]; // #e3a531 (owner-tuned Heimlich gold)
const DEFAULT_CYAN: Rgb = [0.18, 0.576, 0.788]; // #2e93c9 (owner-tuned Heimlich blue)

/**
 * The Heimlich consciousness stream (NIC-60): flowing gold→cyan threads that always own the center,
 * beneath the greeting/actions and the conversation overlay (course-correction A.1). Rendered by the
 * vendored React Bits "Threads" WebGL component behind this seam — swappable for another engine with
 * no other changes. Colour comes from the resolved mode accent (`--ch-accent-*`), so it re-themes via
 * `data-mode`; motion carries the Heimlich state. Falls back to the static gradient when WebGL is
 * unavailable (jsdom/GL-off) — never crashes the dashboard.
 */
export function HeimlichConsciousness({ interactive = false }: HeimlichConsciousnessProps) {
  const { heimlich, mode } = useDashboardState();
  const params = PARAMS[toRibbonState(heimlich.state)];
  const hostRef = useRef<HTMLDivElement>(null);
  const [colors, setColors] = useState<{ a: Rgb; b: Rgb }>({ a: DEFAULT_GOLD, b: DEFAULT_CYAN });

  // Re-read the accent after mount and on mode switch (wait a frame for the data-mode cross-fade).
  useEffect(() => {
    const host = hostRef.current;
    if (!host) return;
    const id = requestAnimationFrame(() =>
      setColors({
        a: readVarAsRgb(host, "--ch-heimlich-primary", DEFAULT_GOLD),
        b: readVarAsRgb(host, "--ch-heimlich-secondary", DEFAULT_CYAN),
      }),
    );
    return () => cancelAnimationFrame(id);
  }, [mode]);

  return (
    <div
      ref={hostRef}
      className="heimlich__ribbon"
      aria-hidden="true"
      style={{ pointerEvents: interactive ? "auto" : "none" }}
    >
      {hasWebGL() ? (
        <Threads
          color={colors.a}
          color2={colors.b}
          amplitude={params.amplitude}
          distance={params.distance}
          speed={params.speed}
        />
      ) : (
        <div className="heimlich__ribbon-fallback" />
      )}
    </div>
  );
}

let webglSupport: boolean | undefined;
/** Feature-detect WebGL once. jsdom returns null → the static gradient fallback renders instead. */
function hasWebGL(): boolean {
  if (webglSupport !== undefined) return webglSupport;
  try {
    const canvas = document.createElement("canvas");
    webglSupport = !!(canvas.getContext("webgl") || canvas.getContext("experimental-webgl"));
  } catch {
    webglSupport = false;
  }
  return webglSupport;
}

/** Resolve `--ch-accent-*` to RGB 0–1 by probing computed `color` (resolves var chains). */
function readVarAsRgb(host: HTMLElement, varName: string, fallback: Rgb): Rgb {
  const probe = document.createElement("span");
  probe.style.cssText = `color: var(${varName}); position: absolute; opacity: 0; pointer-events: none;`;
  host.appendChild(probe);
  const computed = getComputedStyle(probe).color;
  host.removeChild(probe);
  const match = computed.match(/rgba?\(([^)]+)\)/);
  if (!match) return fallback;
  const parts = match[1].split(",").map((n) => parseFloat(n.trim()));
  if (parts.length < 3 || parts.some((n) => Number.isNaN(n))) return fallback;
  return [parts[0] / 255, parts[1] / 255, parts[2] / 255];
}
