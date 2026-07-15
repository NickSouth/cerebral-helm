import { useState } from "react";
import { useBridge } from "../../state/BridgeProvider";
import type { LayoutFrame, LayoutSpec } from "../../bridge/cerebralBridge";
import { humanizeId } from "../labels";
import { LayoutCanvas, type CanvasItem } from "./LayoutCanvas";
import { ReferencePicker, type ReferenceKind } from "../ReferencePicker";
import { useResolvedAppIcons } from "../useResolvedAppIcons";
import { AppGlyph } from "../AppGlyph";

/** A static window being authored: a reference placed at a named frame. */
interface EditorWindow {
  ref: string;
  kind: ReferenceKind;
  frame: LayoutFrame;
  label: string;
}
/** The single hotswap slot: one frame, and the targets that share it at runtime. */
interface HotswapState {
  frame: LayoutFrame;
  targets: { ref: string; kind: ReferenceKind; label: string }[];
}

/** The canvas id of the hotswap slot (distinct from any reference id). */
const HOTSWAP_ID = "__hotswap__";
/** The frame a newly-added window/slot takes until dragged. */
const DEFAULT_FRAME: LayoutFrame = "centered";

/**
 * Per-mode layout authoring (NIC-142): seed from the currently-arranged windows, then
 * place each on a drag/resize canvas that snaps to named frames, add more apps / URLs /
 * Chrome profiles from a Quick Apps-style picker, and author the hotswap slot's targets.
 * Save writes the mode override through the validated path. Live capture + minting are
 * macOS host features; in a plain browser they degrade honestly.
 *
 * Two variants (increment 4): `inline` renders within the Settings Modes panel (the
 * plain-browser fallback); `standalone` fills its own native window
 * (`index.html?surface=layouteditor&mode=<id>`) with a themed header + ×.
 */
export function LayoutEditor({
  modeId,
  label,
  variant = "inline",
  onClose
}: {
  modeId: string;
  label: string;
  variant?: "inline" | "standalone";
  onClose?: () => void;
}) {
  const bridge = useBridge();
  const [statics, setStatics] = useState<EditorWindow[] | null>(null);
  const [hotswap, setHotswap] = useState<HotswapState | null>(null);
  // Resolve each hotswap target's icon the same way the bottom-bar pill does, so the
  // editor chips are icon-first and Chrome-profile aware (NIC-142).
  const resolveIcon = useResolvedAppIcons(hotswap?.targets.map((target) => target.ref) ?? []);
  const [picker, setPicker] = useState<"window" | "hotswap" | null>(null);
  const [status, setStatus] = useState<string | null>(null);

  const capture = async (): Promise<void> => {
    setStatus(null);
    try {
      const result = await bridge.captureLayout();
      const windows = result.windows.map((window) => ({ ...window, label: humanizeId(window.ref) }));
      if (windows.length === 0) {
        setStatics([]);
        setHotswap(null);
        setStatus("No configured app windows are open to capture. Add windows below.");
        return;
      }
      // The first captured window seeds the hotswap slot; the rest are static.
      const [first, ...rest] = windows;
      setStatics(rest);
      setHotswap({ frame: first.frame, targets: [{ ref: first.ref, kind: first.kind, label: first.label }] });
    } catch {
      setStatus("Live capture is available on the macOS host.");
    }
  };

  const changeFrame = (id: string, frame: LayoutFrame): void => {
    if (id === HOTSWAP_ID) {
      setHotswap((current) => (current ? { ...current, frame } : current));
    } else {
      setStatics((current) =>
        current ? current.map((window) => (window.ref === id ? { ...window, frame } : window)) : current
      );
    }
  };

  const removeItem = (id: string): void => {
    if (id === HOTSWAP_ID) {
      setHotswap(null);
    } else {
      setStatics((current) => (current ? current.filter((window) => window.ref !== id) : current));
    }
  };

  const addStatic = (ref: string, kind: ReferenceKind, refLabel: string): void => {
    setStatics((current) => {
      const base = current ?? [];
      if (base.some((window) => window.ref === ref)) {
        return base;
      }
      return [...base, { ref, kind, label: refLabel, frame: DEFAULT_FRAME }];
    });
  };

  const addHotswapTarget = (ref: string, kind: ReferenceKind, refLabel: string): void => {
    setHotswap((current) => {
      if (!current) {
        return { frame: DEFAULT_FRAME, targets: [{ ref, kind, label: refLabel }] };
      }
      if (current.targets.some((target) => target.ref === ref)) {
        return current;
      }
      return { ...current, targets: [...current.targets, { ref, kind, label: refLabel }] };
    });
  };

  const removeHotswapTarget = (ref: string): void => {
    setHotswap((current) => {
      if (!current) {
        return current;
      }
      const targets = current.targets.filter((target) => target.ref !== ref);
      return targets.length === 0 ? null : { ...current, targets };
    });
  };

  const save = async (): Promise<void> => {
    const staticWindows = (statics ?? []).map((window) => ({
      ref: window.ref,
      kind: window.kind,
      frame: window.frame
    }));
    const quickToggle = hotswap
      ? { frame: hotswap.frame, targets: hotswap.targets.map((target) => ({ ref: target.ref, kind: target.kind })) }
      : undefined;
    let windows = staticWindows;
    if (windows.length === 0) {
      // A layout needs at least one window; place the hotswap slot statically too.
      if (hotswap && hotswap.targets.length > 0) {
        const first = hotswap.targets[0];
        windows = [{ ref: first.ref, kind: first.kind, frame: hotswap.frame }];
      } else {
        setStatus("Add at least one window before saving.");
        return;
      }
    }
    // Which physical monitor a layout opens on is now the global "Layout display"
    // setting (NIC-142), not a per-mode choice — `display` is a vestigial contract
    // field the arrange path no longer reads. Send a stable default.
    const layout: LayoutSpec = { display: "primary", windows, quickToggle };
    const result = await bridge.updateLayout({ modeId, layout });
    setStatus(result.accepted ? "Layout saved." : (result.errors[0] ?? "Save failed."));
  };

  const items: CanvasItem[] =
    statics === null
      ? []
      : [
          ...statics.map((window) => ({ id: window.ref, label: window.label, frame: window.frame })),
          ...(hotswap
            ? [
                {
                  id: HOTSWAP_ID,
                  label: `Hotswap · ${hotswap.targets.length}`,
                  frame: hotswap.frame,
                  hotswap: true
                }
              ]
            : [])
        ];

  const controls =
    statics !== null ? (
      <>
        <p className="settings-note">
          Drag each window to move it or its corner to resize; it snaps to the nearest frame. The
          accent rectangle is the hotswap slot.
        </p>
        <LayoutCanvas items={items} onChangeFrame={changeFrame} onRemove={removeItem} />

        <div className="layout-editor__adders">
          <button type="button" className="settings-button" onClick={() => setPicker("window")}>
            Add window
          </button>
        </div>

        <fieldset className="layout-editor__hotswap">
          <legend className="settings-list__sub">Hotswap targets</legend>
          {hotswap && hotswap.targets.length > 0 ? (
            <ul className="layout-editor__hotswap-list">
              {hotswap.targets.map((target) => {
                const icon = resolveIcon(target.ref, target.label);
                return (
                  <li key={target.ref} className="layout-editor__hotswap-chip">
                    <span className="layout-editor__hotswap-chip-icon" aria-hidden="true">
                      {icon.iconPng ? (
                        <img src={`data:image/png;base64,${icon.iconPng}`} alt="" />
                      ) : (
                        <AppGlyph category={icon.fallbackCategory} />
                      )}
                      {icon.profileAvatarPng ? (
                        <img
                          className="layout-editor__hotswap-chip-badge"
                          src={`data:image/png;base64,${icon.profileAvatarPng}`}
                          alt=""
                        />
                      ) : null}
                    </span>
                    <span>{icon.label}</span>
                    <button
                      type="button"
                      className="layout-editor__hotswap-remove"
                      aria-label={`Remove hotswap ${icon.label}`}
                      onClick={() => removeHotswapTarget(target.ref)}
                    >
                      ×
                    </button>
                  </li>
                );
              })}
            </ul>
          ) : (
            <p className="settings-note">No hotswap targets yet.</p>
          )}
          <button type="button" className="settings-button" onClick={() => setPicker("hotswap")}>
            Add hotswap target
          </button>
        </fieldset>

        <button type="button" className="settings-button settings-button--primary" onClick={() => void save()}>
          Save layout
        </button>

        {picker ? (
          <ReferencePicker
            variant="overlay"
            onClose={() => setPicker(null)}
            title={picker === "window" ? "Add a window" : "Add a hotswap window"}
            ariaLabel={picker === "window" ? "Add a window" : "Add a hotswap target"}
            onPick={picker === "window" ? addStatic : addHotswapTarget}
          />
        ) : null}
      </>
    ) : null;

  const captureButton = (
    <button type="button" className="settings-button" onClick={() => void capture()}>
      Capture current windows
    </button>
  );

  if (variant === "standalone") {
    return (
      <div
        className="layout-editor layout-editor--standalone"
        role="dialog"
        aria-modal="true"
        aria-label={`Edit ${label} layout`}
      >
        <header className="layout-editor__header">
          <h2 className="layout-editor__title">Edit {label} layout</h2>
          <button
            type="button"
            className="layout-editor__close"
            aria-label="Close layout editor"
            onClick={onClose}
          >
            ×
          </button>
        </header>
        <div className="layout-editor__body">
          <p className="settings-note">
            Capture your arranged windows, then place them on the canvas and add apps, URLs, or Chrome
            profiles. Author the hotswap slot's targets below.
          </p>
          {captureButton}
          {controls}
          {status ? <p className="settings-note">{status}</p> : null}
        </div>
      </div>
    );
  }

  return (
    <div className="settings-layout-editor">
      <div className="settings-layout-editor__head">
        <span className="settings-list__title">{label}</span>
        {captureButton}
      </div>
      {controls}
      {status ? <p className="settings-note">{status}</p> : null}
    </div>
  );
}

export default LayoutEditor;
