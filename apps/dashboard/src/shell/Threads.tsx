import { useEffect, useRef } from "react";
import { Renderer, Program, Mesh, Triangle, Color } from "ogl";
import "./Threads.css";

/*
 * Vendored from React Bits ("Threads") — https://reactbits.dev/backgrounds/threads
 * (DavidHDev/react-bits, MIT + Commons Clause; used inside the product, not resold).
 * Local modifications for the Heimlich consciousness stream:
 *   - `color2`   : second colour so the threads read as a left→right gradient (gold → cyan).
 *   - `speed`    : scales the flow rate.
 *   - lens amplitude envelope: grounded (slight drift) at both edges, tallest in the middle.
 *   - "renegade" threads that swing wider and break off the bundle.
 *   - a spark layer (subtle sprinkle + occasional brighter pop).
 *   - removed the mouse interaction (uMouse + listeners) — unused, and cheaper without it.
 */

export interface ThreadsProps {
  /** Left/warm colour, RGB 0–1. */
  color?: [number, number, number];
  /** Right/cool colour, RGB 0–1. Defaults to `color` (single-colour) when omitted. */
  color2?: [number, number, number];
  amplitude?: number;
  distance?: number;
  /** Flow-rate multiplier (1 = upstream default). */
  speed?: number;
}

const vertexShader = `
attribute vec2 position;
attribute vec2 uv;
varying vec2 vUv;
void main() {
  vUv = uv;
  gl_Position = vec4(position, 0.0, 1.0);
}
`;

const fragmentShader = `
precision highp float;

uniform float iTime;
uniform vec3 iResolution;
uniform vec3 uColor;
uniform vec3 uColor2;
uniform float uAmplitude;
uniform float uDistance;

#define PI 3.1415926538

const int u_line_count = 30;
const float u_line_width = 4.0; // NIC-77: thinner strands (esp. on large viewports)
const float u_line_blur = 11.0; // softness trimmed to match the thinner lines

float Perlin2D(vec2 P) {
    vec2 Pi = floor(P);
    vec4 Pf_Pfmin1 = P.xyxy - vec4(Pi, Pi + 1.0);
    vec4 Pt = vec4(Pi.xy, Pi.xy + 1.0);
    Pt = Pt - floor(Pt * (1.0 / 71.0)) * 71.0;
    Pt += vec2(26.0, 161.0).xyxy;
    Pt *= Pt;
    Pt = Pt.xzxz * Pt.yyww;
    vec4 hash_x = fract(Pt * (1.0 / 951.135664));
    vec4 hash_y = fract(Pt * (1.0 / 642.949883));
    vec4 grad_x = hash_x - 0.49999;
    vec4 grad_y = hash_y - 0.49999;
    vec4 grad_results = inversesqrt(grad_x * grad_x + grad_y * grad_y)
        * (grad_x * Pf_Pfmin1.xzxz + grad_y * Pf_Pfmin1.yyww);
    grad_results *= 1.4142135623730950;
    vec2 blend = Pf_Pfmin1.xy * Pf_Pfmin1.xy * Pf_Pfmin1.xy
               * (Pf_Pfmin1.xy * (Pf_Pfmin1.xy * 6.0 - 15.0) + 10.0);
    vec4 blend2 = vec4(blend, vec2(1.0 - blend));
    return dot(grad_results, blend2.zxzx * blend2.wwyy);
}

float pixel(float count, vec2 resolution) {
    return (1.0 / max(resolution.x, resolution.y)) * count;
}

float hash1(float n) { return fract(sin(n * 127.1) * 43758.5453); }

// Dense tiny spark points, sized by the lens (tiny at the edges, a bit bigger through the middle).
// The caller confines them to on/near the ribbons.
float sparkLayer(vec2 uv, float time) {
    float total = 0.0;
    float aspect = iResolution.x / max(iResolution.y, 1.0);
    float envX = mix(0.3, 1.0, pow(sin(clamp(uv.x, 0.0, 1.0) * PI), 0.7));
    vec2 grid = vec2(uv.x * aspect, uv.y) * 22.0;
    vec2 gi = floor(grid);
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 cell = gi + vec2(float(x), float(y));
            float h = fract(sin(dot(cell, vec2(12.9, 78.2))) * 43758.5453);
            float h2 = fract(sin(dot(cell, vec2(39.3, 11.1))) * 24634.6531);
            float present = step(0.72, h); // ~28% of cells hold a spark
            vec2 pos = cell + vec2(0.5) + vec2(0.42 * sin(time * 0.6 + h * 6.28), 0.18 * cos(time * 0.4 + h2 * 6.28));
            float d = length(grid - pos);
            float life = 0.5 + 0.5 * sin(time * (0.4 + 0.8 * h) + h2 * 6.28);
            float pop = smoothstep(0.55, 1.0, life);
            float sz = (0.035 + 0.05 * h2) * envX; // tiny; scaled small at edges / bigger mid
            total += smoothstep(sz, 0.0, d) * (0.25 + 0.75 * pop) * present;
        }
    }
    return total;
}

// Base vertical position of a thread at this x — the expensive Perlin work, ONE call per thread.
float threadY(vec2 st, float perc, float time, float amplitude, float distance, float phase) {
    // Lens envelope: grounded (with a small floor for slight drift) at both edges, tallest mid.
    float env = mix(0.12, 1.0, pow(sin(clamp(st.x, 0.0, 1.0) * PI), 0.7));
    float finalAmplitude = env * 0.55 * amplitude;
    float time_scaled = time / 10.0 + phase; // per-thread phase desyncs the threads so they cross

    float xnoise = mix(
        Perlin2D(vec2(time_scaled, st.x + perc) * 2.5),
        Perlin2D(vec2(time_scaled, st.x + time_scaled) * 3.5) / 1.5,
        st.x * 0.3
    );

    float y = 0.5 + (perc - 0.5) * distance + xnoise / 2.0 * finalAmplitude;
    // Hard vertical bound: never above the Heimlich line / below "Good day".
    return 0.5 + clamp(y - 0.5, -0.36, 0.36);
}

// Crisp core coverage of a line at height y — cheap (no noise); called per fork sub-ribbon.
float coreCoverage(vec2 st, float y, float width, float perc) {
    float blur = smoothstep(0.0, 0.2, st.x) * perc;
    float bw = u_line_blur * pixel(1.0, iResolution.xy) * blur;
    float line_start = smoothstep(y + (width / 2.0) + bw, y, st.y);
    float line_end = smoothstep(y, y - (width / 2.0) - bw, st.y);
    float fade = 1.0 - smoothstep(0.0, 1.0, pow(perc, 0.3));
    return clamp((line_start - line_end) * fade, 0.0, 1.0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float line_strength = 1.0;
    float heroGlow = 0.0;
    float bloom = 0.0;

    for (int i = 0; i < u_line_count; i++) {
        float fi = float(i);
        float p = fi / float(u_line_count);
        float seed = hash1(fi + 3.0);
        float seed2 = hash1(fi + 17.0);

        // ~30% loose "splinters": anchored to ONE edge, splintering off past the midpoint.
        float loose = step(0.7, seed2);
        float side = step(0.5, hash1(fi + 41.0)); // 0 = left-anchored, 1 = right-anchored
        float fadeW = 0.1;
        float leftEnd = mix(0.6, 0.88, hash1(fi + 29.0));
        float rightStart = mix(0.12, 0.4, hash1(fi + 29.0));
        float leftWin = 1.0 - smoothstep(leftEnd - fadeW, leftEnd, uv.x);
        float rightWin = smoothstep(rightStart, rightStart + fadeW, uv.x);
        float window = mix(1.0, mix(leftWin, rightWin, side), loose);

        // distance-from-anchor (0 at the anchored edge, 1 at the free/splinter end)
        float tLeft = clamp(uv.x / max(leftEnd, 0.01), 0.0, 1.0);
        float tRight = clamp((1.0 - uv.x) / max(1.0 - rightStart, 0.01), 0.0, 1.0);
        float splitRamp = smoothstep(0.35, 1.0, mix(tLeft, tRight, side)) * loose;
        float forkCount = mix(1.0, 1.0 + floor(hash1(fi + 53.0) * 4.0), loose); // 1..4 for loose

        float phase = seed * 5.0;                       // desync (they cross in the middle)
        float lineAmp = uAmplitude * mix(1.0, 1.25, loose);
        float baseWidth = u_line_width * pixel(1.0, iResolution.xy) * (1.0 - p);

        float y = threadY(uv, p, iTime, lineAmp, uDistance, phase);

        // Bloom (soft emitted light) — once per thread, from the base path.
        float dY = abs(uv.y - y);
        float fade = 1.0 - smoothstep(0.0, 1.0, pow(p, 0.3));
        bloom += exp(-(dY * dY) / (0.055 * 0.055)) * fade * window;

        // Fork loose splinters into up to 4 diverging, thinning sub-ribbons near the free end.
        for (int k = 0; k < 4; k++) {
            float fk = float(k);
            float active = step(fk + 0.5, forkCount);
            float centered = fk - (forkCount - 1.0) * 0.5;
            float yOffset = centered * 0.05 * splitRamp;
            float widthScale = 1.0 - 0.16 * fk;
            float lv = coreCoverage(uv, y + yOffset, baseWidth * widthScale, p) * window * active;
            line_strength *= (1.0 - lv);
            heroGlow += lv * step(fi, 2.5); // first 3 threads glow a touch brighter (foreground)
        }
    }

    // Fade ribbons a few px before the left and right borders.
    float epx = 6.0 / max(iResolution.x, 1.0);
    float edgeFade = smoothstep(0.0, epx, uv.x) * (1.0 - smoothstep(1.0 - epx, 1.0, uv.x));

    // Overlap shouldn't pile up brightness at the converged edges: saturate the bloom with a cap
    // that is low at the edges (a dull glow) and higher through the middle.
    float envX = mix(0.12, 1.0, pow(sin(clamp(uv.x, 0.0, 1.0) * PI), 0.7));
    // NIC-77 (owner: "not nearly as much ethereal glow"): pull the bloom cap well down so the
    // strands read crisp with only a faint halo instead of a wide aura.
    float bloomCap = mix(0.22, 0.55, envX);
    bloom = bloomCap * (1.0 - exp(-bloom / max(bloomCap, 0.001)));

    float colorVal = (1.0 - line_strength) * edgeFade;
    bloom *= edgeFade;
    heroGlow = clamp(heroGlow, 0.0, 1.0) * edgeFade;

    vec3 tint = mix(uColor, uColor2, uv.x); // gold (left) → cyan (right)

    // Sparks confined to on/near the ribbons.
    float prox = clamp(colorVal + bloom * 0.7, 0.0, 1.0);
    float sparkV = sparkLayer(uv, iTime) * smoothstep(0.08, 0.45, prox);

    // Emissive compositing: ribbons are light that IS their colour and tints the dark around them.
    float bloomStrength = 0.22; // NIC-77: reduced bloom — crisp strands, minimal ethereal glow
    vec3 emit = tint * (colorVal + bloom * bloomStrength);
    emit += mix(tint, vec3(1.0), 0.22) * heroGlow * 0.16; // foreground: mostly colour, little white
    emit += mix(tint, vec3(1.0), 0.3) * sparkV;

    // Warm it a touch, then cap brightness in a HUE-PRESERVING way (bright crossings stay coloured).
    emit *= vec3(1.05, 1.0, 0.92);
    float mx = max(emit.r, max(emit.g, emit.b));
    emit = emit / max(mx, 1.0);

    float alpha = clamp(colorVal + bloom * bloomStrength * 0.9 + heroGlow * 0.16 + sparkV, 0.0, 1.0);
    // Premultiplied output (NIC-77): colour is pre-scaled by alpha to match the ONE / ONE_MINUS_SRC_ALPHA
    // blend and the premultiplied drawing buffer, so WKWebView composites the aura at the right level.
    fragColor = vec4(emit * alpha, alpha);
}

void main() {
    mainImage(gl_FragColor, gl_FragCoord.xy);
}
`;

export default function Threads({
  color = [1, 1, 1],
  color2,
  amplitude = 1,
  distance = 0,
  speed = 1,
  ...rest
}: ThreadsProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const animationFrameId = useRef<number>(0);

  const propsRef = useRef({ color, color2, amplitude, distance, speed });
  propsRef.current = { color, color2, amplitude, distance, speed };

  useEffect(() => {
    if (!containerRef.current) return;
    const container = containerRef.current;

    let renderer: Renderer;
    try {
      // Premultiplied-alpha pipeline (NIC-77): WKWebView's LIVE WebGL compositor over-brightens a
      // straight-alpha canvas (the aura blooms), while the raster/snapshot path composites it
      // correctly — which is why the glow looked right only during the old view-transition. Declaring
      // the buffer premultiplied and emitting premultiplied colour (see the shader's final line +
      // ONE / ONE_MINUS_SRC_ALPHA blend) makes the live composite match the correct raster in both
      // WKWebView and browsers.
      renderer = new Renderer({ alpha: true, premultipliedAlpha: true });
    } catch {
      return; // no WebGL — the caller shows its own fallback
    }
    const gl = renderer.gl;
    gl.clearColor(0, 0, 0, 0);
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
    container.appendChild(gl.canvas);

    const initColor = propsRef.current.color;
    let program: Program;
    let mesh: Mesh;
    try {
      const geometry = new Triangle(gl);
      program = new Program(gl, {
        vertex: vertexShader,
        fragment: fragmentShader,
        uniforms: {
          iTime: { value: 0 },
          iResolution: {
            value: new Color(gl.canvas.width, gl.canvas.height, gl.canvas.width / gl.canvas.height)
          },
          uColor: { value: new Color(...initColor) },
          uColor2: { value: new Color(...(propsRef.current.color2 ?? initColor)) },
          uAmplitude: { value: propsRef.current.amplitude },
          uDistance: { value: propsRef.current.distance }
        }
      });
      mesh = new Mesh(gl, { geometry, program });
    } catch {
      // Shader failed to compile/link — degrade to the caller's fallback instead of crashing.
      if (container.contains(gl.canvas)) container.removeChild(gl.canvas);
      return;
    }

    const MAX_RENDER_DIM = 1920;
    function resize() {
      const { clientWidth, clientHeight } = container;
      const baseDpr = Math.min(window.devicePixelRatio || 1, 2);
      const longestSide = Math.max(clientWidth, clientHeight) * baseDpr;
      const dpr = longestSide > MAX_RENDER_DIM ? (baseDpr * MAX_RENDER_DIM) / longestSide : baseDpr;
      renderer.dpr = dpr;
      renderer.setSize(clientWidth, clientHeight);
      program.uniforms.iResolution.value.r = gl.canvas.width;
      program.uniforms.iResolution.value.g = gl.canvas.height;
      program.uniforms.iResolution.value.b = gl.canvas.width / gl.canvas.height;
    }

    const resizeObserver = new ResizeObserver(resize);
    resizeObserver.observe(container);
    window.addEventListener("resize", resize);
    resize();

    let isVisible = true;
    const intersectionObserver = new IntersectionObserver(
      (entries) => {
        isVisible = entries[0].isIntersecting;
      },
      { threshold: 0 }
    );
    intersectionObserver.observe(container);

    function update(t: number) {
      animationFrameId.current = requestAnimationFrame(update);
      if (!isVisible || document.hidden) return;

      const p = propsRef.current;
      program.uniforms.uColor.value.set(...p.color);
      program.uniforms.uColor2.value.set(...(p.color2 ?? p.color));
      program.uniforms.uAmplitude.value = p.amplitude;
      program.uniforms.uDistance.value = p.distance;
      program.uniforms.iTime.value = t * 0.001 * p.speed;

      renderer.render({ scene: mesh });
    }
    animationFrameId.current = requestAnimationFrame(update);

    return () => {
      if (animationFrameId.current) cancelAnimationFrame(animationFrameId.current);
      resizeObserver.disconnect();
      intersectionObserver.disconnect();
      window.removeEventListener("resize", resize);
      if (container.contains(gl.canvas)) container.removeChild(gl.canvas);
      gl.getExtension("WEBGL_lose_context")?.loseContext();
    };
  }, []);

  return <div ref={containerRef} className="threads-container" {...rest} />;
}
