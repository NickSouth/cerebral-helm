import { ModeGlyph } from "./ModeGlyph";
import { useDashboardState } from "../state/DashboardStateProvider";
import { useBridge } from "../state/BridgeProvider";
import { useUiPosture } from "../state/useUiPosture";
import { armModeWave } from "./modeWave";

/**
 * The 4 fixed mode controls with a strong selected state (design spec §5.9), extracted from
 * `RightRail` so the edge sidebar renders the *same* control rather than a second mode surface
 * that could drift from it. The rail wraps this in its `Panel`; the sidebar renders it bare.
 *
 * `labelledBy` points at whatever heading labels the group in the host surface — the rail passes
 * its panel's label id, and a host with no heading of its own passes nothing.
 */
export function ModeSwitcher({ labelledBy }: { labelledBy?: string }) {
  const { mode, modes } = useDashboardState();
  const bridge = useBridge();
  const { readOnly } = useUiPosture();

  return (
    <div className="mode-switcher" role="group" aria-labelledby={labelledBy} aria-label={labelledBy ? undefined : "Mode"}>
      {modes.map((modeView) => {
        const active = modeView.label === mode;
        return (
          <button
            key={modeView.id}
            type="button"
            className="mode-switcher__option"
            data-active={active}
            aria-pressed={active}
            disabled={readOnly}
            aria-disabled={readOnly || undefined}
            title={readOnly ? "Mode switching is paused while the dashboard is read-only" : undefined}
            onClick={(event) => {
              if (!active && !readOnly) {
                // Arm the mode wave from this control's center: the theme change propagates
                // outward from where the user clicked (shell/modeWave.ts).
                const rect = event.currentTarget.getBoundingClientRect();
                armModeWave(rect.left + rect.width / 2, rect.top + rect.height / 2);
                void bridge.applyMode({ modeId: modeView.id });
              }
            }}
          >
            <span className="mode-switcher__icon">
              <ModeGlyph mode={modeView.id} />
            </span>
            <span className="mode-switcher__label">{modeView.label}</span>
          </button>
        );
      })}
    </div>
  );
}
