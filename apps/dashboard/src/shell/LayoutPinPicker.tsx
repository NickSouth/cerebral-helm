import { useBridge } from "../state/BridgeProvider";
import { ReferencePicker } from "./ReferencePicker";

/**
 * The layout hotswap "+" picker (NIC-142): a thin wrapper over the shared
 * {@link ReferencePicker} whose "Add" adds the chosen reference to the ACTIVE layout
 * session's dynamic slot for this session only (`addLayoutTarget`, non-persistent).
 * URL/Chrome-profile routes mint a reference first (handled by the picker), then the
 * returned id is added. Stays open across adds; the ×, Escape, or the scrim close it.
 *
 * Two variants: `overlay` is the in-webview fallback; `standalone` fills the native
 * `index.html?surface=layoutpin` window.
 */
export function LayoutPinPicker({
  onClose,
  variant = "overlay"
}: {
  onClose: () => void;
  variant?: "overlay" | "standalone";
}) {
  const bridge = useBridge();
  return (
    <ReferencePicker
      variant={variant}
      onClose={onClose}
      title="Add a hotswap window"
      ariaLabel="Add a layout window"
      onPick={(referenceId) => {
        void bridge.addLayoutTarget({ ref: referenceId });
      }}
    />
  );
}

export default LayoutPinPicker;
