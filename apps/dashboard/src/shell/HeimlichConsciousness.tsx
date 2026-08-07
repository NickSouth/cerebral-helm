import { useEffect, useRef, useState } from "react";
import { useDashboardState } from "../state/DashboardStateProvider";
import { useSurfaceReceded } from "../state/surfacePresence";
import { FIELD_DURATION_MS, useFieldIntroStart } from "./useStartupIntro";
import Threads from "./Threads";

interface HeimlichConsciousnessProps {
  /** Allow the field to receive pointer events. Decorative by default — never steals clicks. */
  readonly interactive?: boolean;
}

type Rgb = [number, number, number];

/**
 * A single constant flow character for the whole stream (NIC-125). Heimlich has no live runtime
 * yet, so a state-reactive stream (speeding up / growing taller on "thinking") only reads as
 * random, jarring motion to the user — and every state change caused a visible speed shift during
 * quick actions. These are the former calm `idle` values; the stream now looks identical before,
 * during, and after any command. State reactivity can return once Heimlich is live: `Threads`
 * accumulates its clock (NIC-154), so re-introducing per-state speed/amplitude will ease smoothly
 * instead of teleporting the field.
 */
const RIBBON = { amplitude: 1.0, distance: 0, speed: 0.25 } as const;

/**
 * How the stream behaves while the surface is backdrop (NIC-152). It keeps flowing rather than
 * freezing: a stopped field reads as a crashed dashboard, where a slower one reads as resting.
 * Slowing and capping the frame rate together cut the GPU cost roughly fourfold while the motion
 * still looks continuous — and because `Threads` accumulates its clock, the speed change eases in
 * instead of teleporting the noise field (NIC-125/154).
 */
const RECEDED_RIBBON = { speedScale: 0.55, frameIntervalMs: 50 } as const;

/** Stream tint cross-fade duration — matches `--ch-motion-slow` so the WebGL colour eases with the UI. */
const COLOR_FADE_MS = 320;

const DEFAULT_GOLD: Rgb = [0.89, 0.647, 0.192]; // #e3a531 (owner-tuned Heimlich gold)
const DEFAULT_CYAN: Rgb = [0.18, 0.576, 0.788]; // #2e93c9 (owner-tuned Heimlich blue)

/**
 * The Heimlich consciousness stream (NIC-60): flowing gold→cyan threads that always own the center,
 * beneath the greeting/actions (course-correction A.1). Rendered by the vendored React Bits
 * "Threads" WebGL component behind this seam — swappable for another engine with no other changes.
 * Colour comes from the resolved mode accent (`--ch-accent-*`), so it re-themes via `data-mode`;
 * motion runs at a single constant character (NIC-125 — see `RIBBON`). Falls back to the static
 * gradient when WebGL is unavailable (jsdom/GL-off) — never crashes the dashboard.
 */
export function HeimlichConsciousness({ interactive = false }: HeimlichConsciousnessProps) {
  const { mode } = useDashboardState();
  const hostRef = useRef<HTMLDivElement>(null);
  const [colors, setColors] = useState<{ a: Rgb; b: Rgb }>({ a: DEFAULT_GOLD, b: DEFAULT_CYAN });
  const colorsRef = useRef(colors);
  colorsRef.current = colors;
  const receded = useSurfaceReceded();
  // The field owns steps 2–4 of the launch sequence (NIC-157): the herald thread drawing in, the
  // rest flying in from both sides, then the contraction. `null` once startup is over.
  const introStartAt = useFieldIntroStart();
  const reducedMotion = usePrefersReducedMotion();
  const reducedMotionRef = useRef(reducedMotion);
  reducedMotionRef.current = reducedMotion;
  const animate = hasWebGL() && !reducedMotion;

  // Re-tint the stream on mount and on mode switch. The mode wave is a live commit (no view
  // transition freezes the stream — NIC-125), and CSS custom properties jump instantly, so the
  // WebGL colour eases ITSELF from the current tint to the new accent over the token cross-fade
  // duration. The stream re-colours in step with the rest of the UI and never stops flowing.
  useEffect(() => {
    const host = hostRef.current;
    if (!host) return;
    let raf = requestAnimationFrame(() => {
      const from = colorsRef.current;
      const target = {
        a: readVarAsRgb(host, "--ch-heimlich-primary", DEFAULT_GOLD),
        b: readVarAsRgb(host, "--ch-heimlich-secondary", DEFAULT_CYAN)
      };
      const duration = reducedMotionRef.current ? 0 : COLOR_FADE_MS;
      let start = -1;
      const step = (now: number) => {
        if (start < 0) start = now;
        const k = duration > 0 ? Math.min((now - start) / duration, 1) : 1;
        const e = k * k * (3 - 2 * k); // smoothstep
        setColors({ a: lerpRgb(from.a, target.a, e), b: lerpRgb(from.b, target.b, e) });
        if (k < 1) raf = requestAnimationFrame(step);
      };
      raf = requestAnimationFrame(step);
    });
    return () => cancelAnimationFrame(raf);
  }, [mode]);

  return (
    <div
      ref={hostRef}
      className="heimlich__ribbon"
      aria-hidden="true"
      style={{ pointerEvents: interactive ? "auto" : "none" }}
    >
      {animate ? (
        <Threads
          color={colors.a}
          color2={colors.b}
          amplitude={RIBBON.amplitude}
          distance={RIBBON.distance}
          speed={receded ? RIBBON.speed * RECEDED_RIBBON.speedScale : RIBBON.speed}
          frameIntervalMs={receded ? RECEDED_RIBBON.frameIntervalMs : 0}
          introStartAt={introStartAt}
          introDurationMs={FIELD_DURATION_MS}
        />
      ) : (
        <div className="heimlich__ribbon-fallback" />
      )}
    </div>
  );
}

/**
 * Track `prefers-reduced-motion: reduce`. When set, the caller renders the static gradient instead
 * of the animated field. Guards for environments without `matchMedia` (jsdom) — defaults to false.
 */
function usePrefersReducedMotion(): boolean {
  const query = "(prefers-reduced-motion: reduce)";
  const [reduced, setReduced] = useState(() =>
    typeof window !== "undefined" && typeof window.matchMedia === "function"
      ? window.matchMedia(query).matches
      : false
  );
  useEffect(() => {
    if (typeof window === "undefined" || typeof window.matchMedia !== "function") return;
    const mql = window.matchMedia(query);
    const onChange = () => setReduced(mql.matches);
    onChange();
    mql.addEventListener("change", onChange);
    return () => mql.removeEventListener("change", onChange);
  }, []);
  return reduced;
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

/** Linear-interpolate two RGB triplets (each channel 0–1) by k∈[0,1]. */
function lerpRgb(from: Rgb, to: Rgb, k: number): Rgb {
  return [
    from[0] + (to[0] - from[0]) * k,
    from[1] + (to[1] - from[1]) * k,
    from[2] + (to[2] - from[2]) * k
  ];
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
