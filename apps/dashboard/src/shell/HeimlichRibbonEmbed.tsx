import { useEffect, useRef, useState } from "react";
import { sceneForState, UNICORN_SCRIPT_SRC, type HeimlichRibbonState } from "./heimlichRibbon";

interface HeimlichRibbonEmbedProps {
  readonly state: HeimlichRibbonState;
  /**
   * Allow the embed to receive pointer events. The ribbon is decorative by default and must never
   * intercept clicks meant for the greeting/actions above it.
   */
  readonly interactive?: boolean;
}

type EmbedStatus = "idle" | "loading" | "ready" | "fallback";

interface UnicornStudioGlobal {
  isInitialized?: boolean;
  init: () => unknown;
}

declare global {
  interface Window {
    UnicornStudio?: UnicornStudioGlobal;
  }
}

/**
 * The Heimlich ribbon as an embedded external WebGL motion asset (a Unicorn Studio scene) — NOT a
 * hand-built shader (NIC-60, owner decision). This component is only the integration boundary: it
 * reserves a fixed responsive container behind the greeting/actions, lazy-loads the embed after the
 * shell paints, and degrades to a static gradient fallback if there is no scene yet or the embed
 * fails. The ribbon visual itself lives in the external asset, never in code here.
 */
export function HeimlichRibbonEmbed({ state, interactive = false }: HeimlichRibbonEmbedProps) {
  const scene = sceneForState(state);
  const projectId = scene.projectId;
  const [status, setStatus] = useState<EmbedStatus>(projectId ? "idle" : "fallback");

  useEffect(() => {
    // No real scene yet → stay on the fallback; don't load the vendor script.
    if (!projectId) {
      setStatus("fallback");
      return;
    }

    let cancelled = false;
    setStatus("loading");

    // Lazy-load only after the shell UI has rendered.
    const handle = whenIdle(() => {
      loadUnicorn()
        .then((studio) => {
          if (cancelled) return;
          if (!studio.isInitialized) {
            studio.init();
            studio.isInitialized = true;
          }
          setStatus("ready");
        })
        .catch(() => {
          if (!cancelled) setStatus("fallback");
        });
    });

    return () => {
      cancelled = true;
      cancelIdle(handle);
    };
  }, [projectId]);

  const showFallback = status !== "ready";

  return (
    <div
      className="heimlich__ribbon"
      aria-hidden="true"
      data-state={state}
      data-embed-status={status}
      style={{ pointerEvents: interactive ? "auto" : "none" }}
    >
      {projectId ? (
        <div className="heimlich__ribbon-embed" data-us-project={projectId} />
      ) : null}
      {showFallback ? <div className="heimlich__ribbon-fallback" /> : null}
    </div>
  );
}

/** Inject the vendor script once (idempotent) and resolve the global; reject on load failure. */
function loadUnicorn(): Promise<UnicornStudioGlobal> {
  if (window.UnicornStudio) return Promise.resolve(window.UnicornStudio);

  return new Promise((resolve, reject) => {
    const done = () =>
      window.UnicornStudio ? resolve(window.UnicornStudio) : reject(new Error("UnicornStudio global missing"));

    const existing = document.querySelector<HTMLScriptElement>('script[data-unicorn-embed="true"]');
    if (existing) {
      existing.addEventListener("load", done, { once: true });
      existing.addEventListener("error", () => reject(new Error("Unicorn script failed")), { once: true });
      return;
    }

    const script = document.createElement("script");
    script.src = UNICORN_SCRIPT_SRC;
    script.async = true;
    script.dataset.unicornEmbed = "true";
    script.addEventListener("load", done, { once: true });
    script.addEventListener("error", () => reject(new Error("Unicorn script failed")), { once: true });
    document.head.appendChild(script);
  });
}

type IdleHandle = { type: "idle"; id: number } | { type: "timeout"; id: ReturnType<typeof setTimeout> };

/** `requestIdleCallback` where available (defer to after paint), else a short timeout (WKWebView). */
function whenIdle(cb: () => void): IdleHandle {
  if (typeof window.requestIdleCallback === "function") {
    return { type: "idle", id: window.requestIdleCallback(cb, { timeout: 1000 }) };
  }
  return { type: "timeout", id: setTimeout(cb, 200) };
}

function cancelIdle(handle: IdleHandle): void {
  if (handle.type === "idle" && typeof window.cancelIdleCallback === "function") {
    window.cancelIdleCallback(handle.id);
  } else if (handle.type === "timeout") {
    clearTimeout(handle.id);
  }
}
