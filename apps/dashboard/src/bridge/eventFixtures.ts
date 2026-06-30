import type { BridgeEvent } from "./cerebralBridge";
import received from "../../../../packages/contracts/fixtures/valid/lifecycle/received-event.json";
import planned from "../../../../packages/contracts/fixtures/valid/lifecycle/planned-event.json";
import plannedToRunning from "../../../../packages/contracts/fixtures/valid/lifecycle/planned-to-running-event.json";
import plannedToConfirmation from "../../../../packages/contracts/fixtures/valid/lifecycle/planned-to-confirmation-event.json";
import confirmationToRunning from "../../../../packages/contracts/fixtures/valid/lifecycle/confirmation-to-running-event.json";
import confirmationToCancelled from "../../../../packages/contracts/fixtures/valid/lifecycle/confirmation-to-cancelled-event.json";
import runningToSucceeded from "../../../../packages/contracts/fixtures/valid/lifecycle/running-to-succeeded-event.json";
import runningToFailed from "../../../../packages/contracts/fixtures/valid/lifecycle/running-to-failed-event.json";
import runningToCancelled from "../../../../packages/contracts/fixtures/valid/lifecycle/running-to-cancelled-event.json";
import capabilityChangedEvent from "../../../../packages/contracts/fixtures/valid/bridge/events/capability-changed-event.json";

/** The nine canonical command-lifecycle transitions, in state-machine order. */
const lifecycleTransitionFixtures = [
  received,
  planned,
  plannedToRunning,
  plannedToConfirmation,
  confirmationToRunning,
  confirmationToCancelled,
  runningToSucceeded,
  runningToFailed,
  runningToCancelled
];

/**
 * Each canonical lifecycle transition wrapped as a `command.lifecycle.transition` bridge
 * event (the payload is the lifecycle event itself, as the real bridge delivers it).
 */
export const lifecycleBridgeEvents: readonly BridgeEvent[] = lifecycleTransitionFixtures.map((fixture, index) => ({
  eventId: `brevt_lifecycle${String(index + 1).padStart(2, "0")}`,
  type: "command.lifecycle.transition",
  schemaVersion: fixture.schemaVersion,
  timestamp: fixture.timestamp,
  payload: fixture as Readonly<Record<string, unknown>>
}));

/** The canonical capability-change event (system metrics unavailable). */
export const capabilityBridgeEvent: BridgeEvent = {
  eventId: capabilityChangedEvent.eventId,
  type: "bridge.capability.changed",
  schemaVersion: capabilityChangedEvent.schemaVersion,
  timestamp: capabilityChangedEvent.timestamp,
  payload: capabilityChangedEvent.payload as Readonly<Record<string, unknown>>
};
