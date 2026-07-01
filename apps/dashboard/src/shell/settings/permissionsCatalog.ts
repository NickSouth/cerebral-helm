import appOpen from "../../../../../packages/contracts/fixtures/valid/tools/descriptors/app.open.json";
import urlOpen from "../../../../../packages/contracts/fixtures/valid/tools/descriptors/url.open.json";
import hookRun from "../../../../../packages/contracts/fixtures/valid/tools/descriptors/hook.run.json";
import systemStatusRead from "../../../../../packages/contracts/fixtures/valid/tools/descriptors/system.status.read.json";
import noteCapture from "../../../../../packages/contracts/fixtures/valid/tools/descriptors/note.capture.json";
import noteSearch from "../../../../../packages/contracts/fixtures/valid/tools/descriptors/note.search.json";
import modeApply from "../../../../../packages/contracts/fixtures/valid/tools/descriptors/mode.apply.json";

/**
 * A **read-only** mirror of the enabled tools + their deterministic risk/confirmation policy
 * (NIC-63 Permissions). Sourced straight from the authoritative tool descriptors — the same source
 * of truth the risk engine uses (ADR-003) — so the panel inspects real policy, never a fabricated
 * or weaker copy. Like the widget/app registries, this is a pre-Mac frontend mirror; the native
 * bridge delivers the tool catalog later. The UI can display this policy but can never change it —
 * a settings patch that tries (e.g. `toolRiskOverrides`) is rejected by `validateSettingsChanges`.
 */
export interface PermissionTool {
  readonly id: string;
  readonly purpose: string;
  readonly risk: string;
  readonly confirmationPolicyKey?: string;
  readonly requiresConfirmation: boolean;
}

interface RawDescriptor {
  readonly id: string;
  readonly purpose: string;
  readonly risk: string;
  readonly confirmationPolicyKey?: string;
}

/** Only `read_only` tools skip confirmation; every writing/side-effecting risk class confirms. */
function requiresConfirmation(risk: string): boolean {
  return risk !== "read_only";
}

function toPermissionTool(descriptor: RawDescriptor): PermissionTool {
  return {
    id: descriptor.id,
    purpose: descriptor.purpose,
    risk: descriptor.risk,
    confirmationPolicyKey: descriptor.confirmationPolicyKey,
    requiresConfirmation: requiresConfirmation(descriptor.risk)
  };
}

/** Ordered to match `config/defaults/app.json` `enabledToolIds`. */
export const PERMISSION_TOOLS: readonly PermissionTool[] = [
  appOpen,
  urlOpen,
  hookRun,
  systemStatusRead,
  noteCapture,
  noteSearch,
  modeApply
].map((descriptor) => toPermissionTool(descriptor as RawDescriptor));
