import type { DashboardBootstrapState } from "./types";
import type {
  BridgeEvent,
  BridgeEventListener,
  CerebralBridge,
  RecentActivity,
  Unsubscribe
} from "./cerebralBridge";
import { getDashboardConfigBundle, getDashboardFixture, failureStateFixtures } from "../fixtures/canonicalFixtures";
import { capabilityBridgeEvent, confirmationBridgeEvent, lifecycleBridgeEvents } from "./eventFixtures";
import recentActivityResponse from "../../../../packages/contracts/fixtures/valid/bridge/operations/get-recent-activity-response.json";

/** Executive is the default mode (config/defaults/app.json `defaultModeId`; ADR-007). */
const DEFAULT_BOOTSTRAP_KEY = "mode.executive.ready";

const RECENT_ACTIVITY = (recentActivityResponse.payload as { recentActivity: RecentActivity }).recentActivity;

/** Compose a full bootstrap state from the eager config bundle and a per-state snapshot. */
function composeBootstrapState(canonicalKey: string): DashboardBootstrapState {
  return {
    ...getDashboardConfigBundle(),
    ...getDashboardFixture(canonicalKey)
  };
}

/**
 * The static seed used by the pre-bridge state store. NIC-52 B2 replaces the static store
 * with one backed by `createMockCerebralBridge()` without changing consumers.
 */
export function loadBootstrapState(): DashboardBootstrapState {
  return composeBootstrapState(DEFAULT_BOOTSTRAP_KEY);
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

export function createMockCerebralBridge(options: { bootstrapKey?: string } = {}): MockCerebralBridge {
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
    submitCommand() {
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
    updateSettings() {
      return Promise.resolve({ accepted: true });
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
          payload: { canonicalKey: fixture.canonicalKey, category: fixture.category, state: fixture.state }
        });
      }
    },
    replayConfirmation() {
      emit(confirmationBridgeEvent);
    }
  };
}
