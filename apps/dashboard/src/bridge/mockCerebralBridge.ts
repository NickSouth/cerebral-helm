import type { DashboardBootstrapState } from "./types";
import type {
  BridgeEvent,
  BridgeEventListener,
  CerebralBridge,
  RecentActivity,
  SettingsSnapshot,
  Unsubscribe
} from "./cerebralBridge";
import {
  getDashboardConfigBundle,
  getDashboardFixture,
  failureStateFixtures
} from "../fixtures/canonicalFixtures";
import {
  capabilityBridgeEvent,
  confirmationBridgeEvent,
  lifecycleBridgeEvents
} from "./eventFixtures";
import { validateSettingsChanges } from "../shell/settings/settingsPatch";
import recentActivityResponse from "../../../../packages/contracts/fixtures/valid/bridge/operations/get-recent-activity-response.json";

/** Executive is the default mode (config/defaults/app.json `defaultModeId`; ADR-007). */
const DEFAULT_BOOTSTRAP_KEY = "mode.executive.ready";

const RECENT_ACTIVITY = (recentActivityResponse.payload as { recentActivity: RecentActivity })
  .recentActivity;

/** Compose a full bootstrap state from the eager config bundle and a per-state snapshot. */
function composeBootstrapState(canonicalKey: string): DashboardBootstrapState {
  return {
    ...getDashboardConfigBundle(),
    ...getDashboardFixture(canonicalKey)
  };
}

/**
 * The static seed used by the pre-bridge state store. NIC-52 B2 replaces the static store
 * with one backed by `createMockCerebralBridge()` without changing consumers. A caller may
 * seed a non-default canonical state (e.g. a degraded state for preview/tests — NIC-64).
 */
export function loadBootstrapState(
  bootstrapKey: string = DEFAULT_BOOTSTRAP_KEY
): DashboardBootstrapState {
  return composeBootstrapState(bootstrapKey);
}

/**
 * A `CerebralBridge` plus replay controls so stories and tests can drive the canonical
 * lifecycle and failure fixtures through the same contract the components consume.
 */
export interface MockCerebralBridge extends CerebralBridge {
  /** Emit one event to all current subscribers. */
  emit(event: BridgeEvent): void;
  /** Replay every canonical command-lifecycle transition as bridge events. */
  replayLifecycle(): void;
  /** Replay the capability change plus every canonical failure / degraded state. */
  replayFailures(): void;
  /** Surface the canonical policy-owned confirmation (a `confirmation.changed` disclosure). */
  replayConfirmation(): void;
}

/** Fold an accepted settings-patch `changes` delta into a snapshot — the mock's stand-in for
 *  the store's merge, so getSettings + settings.changed reflect writes (NIC-137). */
function mergeSettingsChanges(
  prev: SettingsSnapshot,
  changes: Record<string, unknown>
): SettingsSnapshot {
  const appearance = changes.appearance as { reducedMotion?: unknown; assistantName?: unknown } | undefined;
  const knowledge = changes.knowledge as { rootReference?: unknown } | undefined;
  const workspace = changes.workspace as { windowsStoredByMode?: unknown; mainDisplayId?: unknown } | undefined;
  return {
    schemaVersion: prev.schemaVersion,
    defaultModeId: typeof changes.defaultModeId === "string" ? changes.defaultModeId : prev.defaultModeId,
    confirmAllActions:
      typeof changes.confirmAllActions === "boolean" ? changes.confirmAllActions : prev.confirmAllActions,
    appearance: {
      reducedMotion:
        typeof appearance?.reducedMotion === "boolean" ? appearance.reducedMotion : prev.appearance.reducedMotion,
      assistantName:
        typeof appearance?.assistantName === "string" ? appearance.assistantName : prev.appearance.assistantName
    },
    knowledge: {
      rootReference:
        typeof knowledge?.rootReference === "string" ? knowledge.rootReference : prev.knowledge.rootReference
    },
    workspace: {
      windowsStoredByMode:
        typeof workspace?.windowsStoredByMode === "boolean"
          ? workspace.windowsStoredByMode
          : prev.workspace.windowsStoredByMode,
      mainDisplayId:
        typeof workspace?.mainDisplayId === "string" ? workspace.mainDisplayId : prev.workspace.mainDisplayId
    },
    modeColors:
      changes.modeColors && typeof changes.modeColors === "object"
        ? (changes.modeColors as Record<string, string>)
        : prev.modeColors
  };
}

export function createMockCerebralBridge(
  options: { bootstrapKey?: string } = {}
): MockCerebralBridge {
  const bootstrapKey = options.bootstrapKey ?? DEFAULT_BOOTSTRAP_KEY;
  const listeners = new Set<BridgeEventListener>();
  // Representative persisted settings, held mutably so updateSettings visibly persists +
  // broadcasts a settings.changed event (mirrors the real bridge; NIC-141/137).
  let settingsSnapshot: SettingsSnapshot = {
    schemaVersion: "1.0.0",
    defaultModeId: "developer",
    confirmAllActions: false,
    appearance: { reducedMotion: false, assistantName: "Heimlich" },
    knowledge: { rootReference: "knowledge-root" },
    workspace: { windowsStoredByMode: true, mainDisplayId: "system-primary" },
    modeColors: {}
  };
  let settingsEventSeq = 0;

  function emit(event: BridgeEvent): void {
    // Snapshot so a listener that unsubscribes mid-dispatch can't mutate the live set.
    for (const listener of [...listeners]) {
      listener(event);
    }
  }

  return {
    getBootstrapState() {
      return Promise.resolve(composeBootstrapState(bootstrapKey));
    },
    getRecentActivity() {
      return Promise.resolve(RECENT_ACTIVITY);
    },
    submitCommand(input) {
      // A `run <workflowId>` submission simulates the runtime's workflow execution
      // (NIC-85): a canned two-step progress sequence bracketed by lifecycle
      // transitions, so the progress renderer and store paths are exercisable in
      // the browser. It is visibly a simulation — the mock never claims a native
      // step actually ran.
      const workflowId = input.rawInput.startsWith("run ")
        ? input.rawInput.slice("run ".length).trim()
        : null;
      if (workflowId) {
        const commandId = "cmd_000000000000000000000002";
        const at = "2026-06-23T16:00:00.000Z";
        const progress = (
          actionId: string,
          status: string,
          index: number,
          suffix: string
        ): BridgeEvent => ({
          eventId: `brevt_run_${workflowId}_${suffix}`,
          type: "workflow.action.progress",
          schemaVersion: "1.0.0",
          timestamp: at,
          payload: {
            commandId,
            workflowId,
            actionId,
            kind: "mock.step",
            status,
            index,
            total: 2
          }
        });
        const lifecycle = (currentStatus: string): BridgeEvent => ({
          eventId: `brevt_run_${workflowId}_${currentStatus}`,
          type: "command.lifecycle.transition",
          schemaVersion: "1.0.0",
          timestamp: at,
          payload: { commandId, currentStatus }
        });
        // Staggered so the progress line is actually visible in the browser; the
        // sequence and payloads stay deterministic.
        emit(lifecycle("running"));
        emit(progress("step-one", "running", 1, "1r"));
        const later: ReadonlyArray<[BridgeEvent, number]> = [
          [progress("step-one", "succeeded", 1, "1s"), 400],
          [progress("step-two", "running", 2, "2r"), 500],
          [progress("step-two", "succeeded", 2, "2s"), 900],
          [lifecycle("succeeded"), 1000]
        ];
        for (const [event, delay] of later) {
          setTimeout(() => emit(event), delay);
        }
        return Promise.resolve({ commandId, accepted: true });
      }
      return Promise.resolve({ commandId: "cmd_000000000000000000000001", accepted: true });
    },
    applyMode(input) {
      // Eager config is already in state, so a switch needs no round-trip: emit the target
      // mode's resolved snapshot as a `config.changed` event the store folds in (the theme
      // re-themes via data-mode; the heavy region data resolves on switch).
      try {
        const snapshot = getDashboardFixture(`mode.${input.modeId}.ready`);
        emit({
          eventId: `brevt_applymode_${input.modeId}`,
          type: "config.changed",
          schemaVersion: "1.0.0",
          timestamp: "2026-06-23T16:00:00.000Z",
          payload: { snapshot }
        });
        return Promise.resolve({ modeId: input.modeId, status: "ok" as const });
      } catch {
        return Promise.resolve({ modeId: input.modeId, status: "error" as const });
      }
    },
    captureNote() {
      return Promise.resolve({ noteId: "note_000000000000000000000001" });
    },
    searchNotes() {
      return Promise.resolve({ results: [] });
    },
    decideConfirmation(input) {
      // The UI submits the decision; the bridge owns the resulting state change. Clearing the
      // active confirmation is an event, not a UI-local mutation (the real bridge would also
      // drive the command lifecycle forward) — keeps the surface event-driven and honest.
      emit({
        eventId: "brevt_confcleared01",
        type: "confirmation.changed",
        schemaVersion: "1.0.0",
        timestamp: "2026-06-23T16:00:45.000Z",
        payload: { confirmation: null }
      });
      return Promise.resolve({ confirmationId: input.id, decision: input.decision });
    },
    updateSettings(input) {
      // Stand in for the bridge's config validation path (FR-CFG-04): validate the patch's changes
      // against the settings-patch allowlist. A disallowed change (e.g. a risk override) is rejected
      // here exactly as the schema would reject it — the UI never gets a bespoke, weaker path.
      const changes = (input.patch as { changes?: unknown }).changes;
      const { valid } = validateSettingsChanges(changes);
      if (valid) {
        // Persist into the mutable snapshot and broadcast, mirroring the real bridge so a
        // Save visibly re-syncs every surface (assistant name, mode colors) live (NIC-137).
        settingsSnapshot = mergeSettingsChanges(settingsSnapshot, (changes as Record<string, unknown>) ?? {});
        settingsEventSeq += 1;
        emit({
          eventId: `brevt_settings${String(settingsEventSeq).padStart(8, "0")}`,
          type: "settings.changed",
          schemaVersion: "1.0.0",
          timestamp: "2026-07-10T16:00:00.000Z",
          payload: { settings: settingsSnapshot }
        });
      }
      return Promise.resolve({ accepted: valid });
    },
    getSettings() {
      // The mutable snapshot (seeded with representative non-defaults) so browser previews prove
      // the settings UI reads stored state and reflects saves (NIC-141/137).
      return Promise.resolve(settingsSnapshot);
    },
    listApps() {
      // A representative installed-app set for browser previews of the More Apps
      // picker (NIC-119). No icons — the honest non-Mac fallback glyph renders.
      // `referenceId` mirrors the bridge's join onto configured app references:
      // only reference-backed apps are pinnable.
      return Promise.resolve({
        apps: [
          { bundleId: "com.apple.Safari", name: "Safari", referenceId: null },
          { bundleId: "com.apple.mail", name: "Mail", referenceId: null },
          { bundleId: "com.apple.Terminal", name: "Terminal", referenceId: "terminal" },
          { bundleId: "com.microsoft.VSCode", name: "Visual Studio Code", referenceId: "vscode" },
          { bundleId: "com.anthropic.claudefordesktop", name: "Claude", referenceId: "claude-desktop" }
        ],
        truncated: false
      });
    },
    updateQuickApps(input) {
      // Stand in for the validated override path (NIC-119c): the same
      // reference-existence check the bridge applies, accepted otherwise.
      const known = new Set(["terminal", "vscode", "claude-desktop", "xcode"]);
      const unknown = input.quickApps.filter((id) => !known.has(id));
      if (unknown.length > 0) {
        return Promise.resolve({
          accepted: false,
          quickApps: input.quickApps,
          errors: unknown.map((id) => `"${id}" is not a configured app reference.`)
        });
      }
      // An accepted write emits mode.quickapps.changed, mirroring the native
      // bridge (NIC-149) — tiles refresh from the event, never optimistically.
      emit({
        eventId: "brevt_mock_quickapps_changed",
        type: "mode.quickapps.changed",
        schemaVersion: "1.0.0",
        timestamp: new Date().toISOString(),
        payload: { modeId: input.modeId, quickApps: [...input.quickApps] }
      });
      return Promise.resolve({ accepted: true, quickApps: input.quickApps, errors: [] });
    },
    runSpeedTest() {
      // A representative measurement for browser previews (NIC-135). The short
      // delay lets the widget's progress ring animate the way the ~30s native
      // run would; the real bridge resolves when networkQuality completes.
      return new Promise((resolve) => {
        setTimeout(
          () => resolve({ status: "ok", downloadMbps: 243.7, uploadMbps: 17.9, testedAt: new Date().toISOString() }),
          2600
        );
      });
    },
    subscribe(listener): Unsubscribe {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    emit,
    replayLifecycle() {
      for (const event of lifecycleBridgeEvents) {
        emit(event);
      }
    },
    replayFailures() {
      emit(capabilityBridgeEvent);
      for (const fixture of failureStateFixtures) {
        emit({
          eventId: `brevt_${fixture.id}`,
          type: "system.status.changed",
          schemaVersion: "1.0.0",
          timestamp: fixture.clock,
          payload: {
            canonicalKey: fixture.canonicalKey,
            category: fixture.category,
            state: fixture.state
          }
        });
      }
    },
    replayConfirmation() {
      emit(confirmationBridgeEvent);
    }
  };
}
