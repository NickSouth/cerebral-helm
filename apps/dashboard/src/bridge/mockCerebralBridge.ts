import type { DashboardBootstrapState } from "./types";
import type {
  BridgeEvent,
  BridgeEventListener,
  CerebralBridge,
  RecentActivity,
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

export function createMockCerebralBridge(
  options: { bootstrapKey?: string } = {}
): MockCerebralBridge {
  const bootstrapKey = options.bootstrapKey ?? DEFAULT_BOOTSTRAP_KEY;
  const listeners = new Set<BridgeEventListener>();

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
      return Promise.resolve({ accepted: valid });
    },
    listApps() {
      // A representative installed-app set for browser previews of the More Apps
      // picker (NIC-119). No icons — the honest non-Mac fallback glyph renders.
      return Promise.resolve({
        apps: [
          { bundleId: "com.apple.Safari", name: "Safari" },
          { bundleId: "com.apple.mail", name: "Mail" },
          { bundleId: "com.apple.Notes", name: "Notes" },
          { bundleId: "com.microsoft.VSCode", name: "Visual Studio Code" },
          { bundleId: "com.anthropic.claudefordesktop", name: "Claude" }
        ],
        truncated: false
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
