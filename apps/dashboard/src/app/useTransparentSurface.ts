import { useEffect } from "react";

/**
 * Make a standalone surface's document genuinely transparent, so the desktop shows through
 * everything the surface does not paint itself.
 *
 * **This is not optional decoration — without it a transparent window is transparent over nothing.**
 * Three separate layers paint an opaque background before any surface CSS runs:
 *
 * - `html` carries `background: var(--ch-bg-base)` as a solid fallback,
 * - `.app-root` (from `ThemeProvider`, wrapped around *every* surface) carries the mode-tinted
 *   gradient, which is the one that actually shows,
 * - `body` contributes margin that would otherwise offset the surface inside its window.
 *
 * All three are global rules serving the dashboard, which fills its screen and wants an opaque
 * backdrop. A surface hosted in its own small window wants the exact opposite, and CSS alone cannot
 * say so: the rules live above anything a surface can select. `ModeMenuApp` discovered this and
 * cleared them imperatively; the sidebar and the window manager did not, which is why setting
 * `isOpaque = false` on their windows and removing every wash from their CSS changed nothing at all
 * — a fully "transparent" surface was still painting `--ch-bg-base` across its whole window.
 *
 * Restores the previous inline values on unmount, so a surface that shares a document with another
 * (tests, the browser preview) cannot strand it transparent.
 */
export function useTransparentSurface(): void {
  useEffect(() => {
    const targets: HTMLElement[] = [document.documentElement, document.body];
    const appRoot = document.querySelector<HTMLElement>(".app-root");
    if (appRoot) {
      targets.push(appRoot);
    }

    const previous = targets.map((element) => ({
      background: element.style.background,
      margin: element.style.margin,
      overflow: element.style.overflow
    }));

    for (const element of targets) {
      element.style.background = "transparent";
      element.style.margin = "0";
      // These windows are sized to their content. A stray scrollbar on an ancestor would both
      // steal width and paint a platform-coloured track across a surface built to have none.
      element.style.overflow = "hidden";
    }

    return () => {
      targets.forEach((element, index) => {
        element.style.background = previous[index].background;
        element.style.margin = previous[index].margin;
        element.style.overflow = previous[index].overflow;
      });
    };
  }, []);
}

export default useTransparentSurface;
