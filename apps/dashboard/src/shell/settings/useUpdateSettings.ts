import { useBridge } from "../../state/BridgeProvider";
import { buildSettingsPatch, type SettingsPatchChanges } from "./settingsPatch";

/**
 * Submit a settings edit (NIC-63): wrap a `changes` delta in a schema-shaped patch and send it
 * through `bridge.updateSettings` — the same validated config path the real bridge uses (FR-CFG-04).
 * Live-apply: each edit is its own patch, submitted immediately (no Save step). Returns the bridge
 * acceptance so a caller can react to a rejection.
 */
export function useUpdateSettings() {
  const bridge = useBridge();
  return (changes: SettingsPatchChanges) =>
    // The bridge input is an open record; the patch is the schema-shaped settings-patch.
    bridge.updateSettings({
      patch: buildSettingsPatch(changes) as unknown as Readonly<Record<string, unknown>>
    });
}
