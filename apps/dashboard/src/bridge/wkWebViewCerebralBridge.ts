import type { DashboardBootstrapState } from "./types";
import type {
  AddChromeProfileResult,
  AddUrlReferenceResult,
  ApplyModeResult,
  ChromeProfilesResult,
  BridgeEvent,
  BridgeEventListener,
  BridgeEventType,
  CaptureNoteResult,
  CerebralBridge,
  CloseLayoutResult,
  CommandReceipt,
  DecideConfirmationResult,
  CaptureLayoutResult,
  ListAppsResult,
  ListCalendarsResult,
  ChooseFolderResult,
  CreateLinearIssueResult,
  CreateSpotifyPlaylistResult,
  ListMessageRecipientsResult,
  ListSportsEventsResult,
  SendMessageResult,
  ScaffoldProjectResult,
  ListLinearOptionsResult,
  GetLinearProjectCycleResult,
  CloneRepositoryResult,
  CreateCalendarEventResult,
  CanvasStatus,
  KnowledgeRebuildResult,
  ListNotesResult,
  ListCoursesResult,
  ComposeReportResult,
  RunSystemChecksResult,
  ConnectGmailInput,
  ConnectGmailResult,
  UnreadMailResult,
  CreateCourseNoteInput,
  CreateCourseNoteResult,
  ListUrlsResult,
  OpenLayoutResult,
  PinLayoutWindowResult,
  AddLayoutTargetResult,
  ToggleModeCollapseResult,
  WindowInventory,
  WindowActionResult,
  ToggleLayoutResult,
  UpdateLayoutResult,
  RecentActivity,
  RecentActivityQuery,
  SearchNotesResult,
  ConnectSpotifyResult,
  DeleteSecretResult,
  SecretStatusResult,
  SettingsSnapshot,
  SpeedTestResult,
  StoreSecretResult,
  SuggestCommandsResult,
  Unsubscribe,
  UpdateQuickAppsResult,
  UpdateSettingsResult
} from "./cerebralBridge";

/**
 * The macOS WKWebView transport for the versioned `CerebralBridge` (NIC-74c, ADR-004).
 *
 * It is the native-side counterpart of the mock: the dashboard posts JSON bridge
 * messages to `window.webkit.messageHandlers.cerebral` and receives replies through the
 * `window.__cerebralReceive(json)` callback installed here. Operation requests are
 * correlated by `messageId`; event messages are dispatched to subscribers. React
 * components never branch on transport — only `createDashboardRuntime` chooses this
 * implementation over the mock, and it satisfies the same `CerebralBridge` contract.
 */

interface WebKitMessageHandler {
  postMessage(message: unknown): void;
}

interface CerebralWindow extends Window {
  webkit?: { messageHandlers?: { cerebral?: WebKitMessageHandler } };
  __cerebralReceive?: (json: string) => void;
  __cerebralBootstrap?: DashboardBootstrapState;
}

const SCHEMA_VERSION = "1.0.0";
const UI_VERSION = "0.1.0";
const SUPPORTED_BRIDGE_MAJOR = 1;
const SUPPORTED_BRIDGE_MINOR_FLOOR = 0;

const EVENT_TYPES: ReadonlySet<string> = new Set<BridgeEventType>([
  "command.lifecycle.transition",
  "confirmation.changed",
  "system.status.changed",
  "config.changed",
  "mode.quickapps.changed",
  "settings.changed",
  "bridge.capability.changed",
  "workflow.action.progress",
  "display.topology.changed",
  "layout.session.changed",
  "mode.windowcollapse.changed",
  "widget.data.changed",
  "weather.changed",
  "news.changed",
  "mail.changed",
  "system.checks.changed",
  "report.composition.changed",
  "schedule.changed",
  "apps.changed"
]);

/** True when running inside the native shell (the message handler is registered). */
export function isNativeBridgeAvailable(): boolean {
  if (typeof window === "undefined") {
    return false;
  }
  return Boolean((window as CerebralWindow).webkit?.messageHandlers?.cerebral);
}

/** The bootstrap state the native shell injects synchronously before the app loads. */
export function readInjectedBootstrap(): DashboardBootstrapState | undefined {
  if (typeof window === "undefined") {
    return undefined;
  }
  return (window as CerebralWindow).__cerebralBootstrap;
}

function newMessageId(): string {
  const raw = globalThis.crypto?.randomUUID?.() ?? `${Date.now()}-${Math.random()}`;
  return `brmsg_${raw.replace(/[^A-Za-z0-9_-]/g, "")}`.slice(0, 70);
}

interface PendingOperation {
  readonly resolve: (payload: Record<string, unknown>) => void;
  readonly reject: (error: Error) => void;
}

export function createWKWebViewCerebralBridge(): CerebralBridge {
  const win = window as CerebralWindow;
  const handler = win.webkit?.messageHandlers?.cerebral;
  const pending = new Map<string, PendingOperation>();
  const listeners = new Set<BridgeEventListener>();

  function dispatchEvent(event: BridgeEvent): void {
    for (const listener of [...listeners]) {
      listener(event);
    }
  }

  // The handshake's capability replay must reach the store even if the response
  // lands before the store subscribes: buffer it and flush to the first listener.
  const bufferedCapabilityEvents: BridgeEvent[] = [];
  function dispatchOrBufferCapability(event: BridgeEvent): void {
    if (listeners.size === 0) {
      bufferedCapabilityEvents.push(event);
      return;
    }
    dispatchEvent(event);
  }

  // Native → dashboard: operation responses (correlated by messageId), the handshake
  // response, and the event stream.
  win.__cerebralReceive = (json: string) => {
    let message: Record<string, unknown>;
    try {
      message = JSON.parse(json) as Record<string, unknown>;
    } catch {
      return;
    }
    const type = message.type as string | undefined;

    if (type === "bridge.operation.response") {
      const entry = pending.get(message.messageId as string);
      if (!entry) {
        return;
      }
      pending.delete(message.messageId as string);
      if (message.status === "error") {
        const error = message.error as { message?: string } | undefined;
        entry.reject(new Error(error?.message ?? "Bridge operation failed."));
      } else {
        entry.resolve((message.payload as Record<string, unknown>) ?? {});
      }
      return;
    }

    if (type === "bridge.handshake.response") {
      // Replay the handshake's capability set as capability-changed events so the
      // store's availability map seeds without widening the bootstrap contract
      // (FR-SHL-06); runtime rechecks (NIC-83) then flow through the same type.
      const capabilities = message.capabilities as
        | ReadonlyArray<{ id?: string; available?: boolean; degradedReason?: string | null }>
        | undefined;
      for (const capability of capabilities ?? []) {
        if (!capability?.id) {
          continue;
        }
        dispatchOrBufferCapability({
          eventId: newMessageId().replace("brmsg_", "brevt_"),
          type: "bridge.capability.changed",
          schemaVersion: SCHEMA_VERSION,
          timestamp: new Date().toISOString(),
          payload: { capability }
        });
      }
      // An incompatible major version forces read-only recovery, surfaced through the
      // same status event the store folds (FR-SHL-05).
      if (message.compatible === false) {
        const recovery = message.recovery as { remediation?: string } | undefined;
        dispatchEvent({
          eventId: newMessageId().replace("brmsg_", "brevt_"),
          type: "system.status.changed",
          schemaVersion: SCHEMA_VERSION,
          timestamp: new Date().toISOString(),
          payload: {
            category: "bridge_failure",
            state: {
              status: "read_only",
              message: recovery?.remediation ?? "This app is incompatible with the dashboard."
            }
          }
        });
      }
      return;
    }

    if (typeof type === "string" && EVENT_TYPES.has(type)) {
      dispatchEvent({
        eventId: message.eventId as string,
        type: type as BridgeEventType,
        schemaVersion: message.schemaVersion as string,
        timestamp: message.timestamp as string,
        payload: (message.payload as Record<string, unknown>) ?? {}
      });
    }
  };

  function send(message: Record<string, unknown>): void {
    handler?.postMessage(JSON.stringify(message));
  }

  function operation<T>(operationName: string, payload: Record<string, unknown>): Promise<T> {
    const messageId = newMessageId();
    return new Promise<T>((resolve, reject) => {
      pending.set(messageId, {
        resolve: (value) => resolve(value as T),
        reject
      });
      send({
        schemaVersion: SCHEMA_VERSION,
        messageId,
        type: "bridge.operation.request",
        operation: operationName,
        payload
      });
    });
  }

  // Announce the UI's supported bridge version so the shell can report compatibility.
  send({
    schemaVersion: SCHEMA_VERSION,
    messageId: newMessageId(),
    type: "bridge.handshake.request",
    uiVersion: UI_VERSION,
    supportedBridgeMajor: SUPPORTED_BRIDGE_MAJOR,
    supportedBridgeMinorFloor: SUPPORTED_BRIDGE_MINOR_FLOOR
  });

  return {
    getBootstrapState() {
      const injected = readInjectedBootstrap();
      if (injected) {
        return Promise.resolve(injected);
      }
      return operation<DashboardBootstrapState>("getBootstrapState", {});
    },
    getRecentActivity(query?: RecentActivityQuery) {
      return operation<{ recentActivity: RecentActivity }>(
        "getRecentActivity",
        (query as Record<string, unknown>) ?? {}
      ).then((result) => result.recentActivity);
    },
    submitCommand(input) {
      return operation<CommandReceipt>("submitCommand", { ...input });
    },
    suggestCommands(input) {
      return operation<SuggestCommandsResult>("suggestCommands", { ...input });
    },
    applyMode(input) {
      return operation<ApplyModeResult>("applyMode", { ...input });
    },
    captureNote(input) {
      return operation<CaptureNoteResult>("captureNote", { ...input });
    },
    searchNotes(input) {
      return operation<SearchNotesResult>("searchNotes", { ...input });
    },
    decideConfirmation(input) {
      return operation<DecideConfirmationResult>("decideConfirmation", { ...input });
    },
    updateSettings(input) {
      return operation<UpdateSettingsResult>("updateSettings", { ...input });
    },
    getSettings() {
      return operation<SettingsSnapshot>("getSettings", {});
    },
    storeSecret(input) {
      return operation<StoreSecretResult>("storeSecret", { ...input });
    },
    getSecretStatus(input) {
      return operation<SecretStatusResult>("getSecretStatus", { ...input });
    },
    deleteSecret(input) {
      return operation<DeleteSecretResult>("deleteSecret", { ...input });
    },
    connectSpotify() {
      return operation<ConnectSpotifyResult>("connectSpotify", {});
    },
    listUnreadMail(limit?: number) {
      return operation<UnreadMailResult>("listUnreadMail", limit === undefined ? {} : { limit });
    },
    connectGmail(input?: ConnectGmailInput) {
      return operation<ConnectGmailResult>("connectGmail", { ...(input ?? {}) });
    },
    listApps() {
      return operation<ListAppsResult>("listApps", {});
    },
    getCanvasStatus() {
      return operation<CanvasStatus>("getCanvasStatus", {});
    },
    resetCanvas() {
      return operation<CanvasStatus>("resetCanvas", {});
    },
    setCanvasItemHidden(id: string, hidden: boolean) {
      return operation<CanvasStatus>("setCanvasItemHidden", { id, hidden });
    },
    rebuildKnowledgeIndex() {
      return operation<KnowledgeRebuildResult>("rebuildKnowledgeIndex", {});
    },
    composeReport(reportId: string) {
      return operation<ComposeReportResult>("composeReport", { reportId });
    },
    runSystemChecks() {
      return operation<RunSystemChecksResult>("runSystemChecks", {});
    },
    listCourses(limit?: number) {
      return operation<ListCoursesResult>("listCourses", limit === undefined ? {} : { limit });
    },
    createCourseNote(input: CreateCourseNoteInput) {
      return operation<CreateCourseNoteResult>("createCourseNote", { ...input });
    },
    listNotes(limit?: number) {
      return operation<ListNotesResult>("listNotes", limit === undefined ? {} : { limit });
    },
    listCalendars() {
      return operation<ListCalendarsResult>("listCalendars", {});
    },
    createCalendarEvent(input) {
      return operation<CreateCalendarEventResult>("createCalendarEvent", { ...input });
    },
    cloneRepository(input) {
      return operation<CloneRepositoryResult>("cloneRepository", { ...input });
    },
    chooseFolder() {
      return operation<ChooseFolderResult>("chooseFolder", {});
    },
    listLinearOptions() {
      return operation<ListLinearOptionsResult>("listLinearOptions", {});
    },
    getLinearProjectCycle(project) {
      return operation<GetLinearProjectCycleResult>("getLinearProjectCycle", { project });
    },
    createLinearIssue(input) {
      return operation<CreateLinearIssueResult>("createLinearIssue", { ...input });
    },
    createSpotifyPlaylist(input) {
      return operation<CreateSpotifyPlaylistResult>("createSpotifyPlaylist", { ...input });
    },
    scaffoldProject(input) {
      return operation<ScaffoldProjectResult>("scaffoldProject", { ...input });
    },
    listSportsEvents() {
      return operation<ListSportsEventsResult>("listSportsEvents", {});
    },
    listMessageRecipients() {
      return operation<ListMessageRecipientsResult>("listMessageRecipients", {});
    },
    sendMessage(input) {
      return operation<SendMessageResult>("sendMessage", { ...input });
    },
    updateQuickApps(input) {
      return operation<UpdateQuickAppsResult>("updateQuickApps", { ...input });
    },
    addUrlReference(input) {
      return operation<AddUrlReferenceResult>("addUrlReference", { ...input });
    },
    listUrls() {
      return operation<ListUrlsResult>("listUrls", {});
    },
    listChromeProfiles() {
      return operation<ChromeProfilesResult>("listChromeProfiles", {});
    },
    addChromeProfileReference(input) {
      return operation<AddChromeProfileResult>("addChromeProfileReference", { ...input });
    },
    runSpeedTest() {
      return operation<SpeedTestResult>("runSpeedTest", {});
    },
    openLayout(input) {
      return operation<OpenLayoutResult>("openLayout", { ...input });
    },
    closeLayout() {
      return operation<CloseLayoutResult>("closeLayout", {});
    },
    toggleLayout(input) {
      return operation<ToggleLayoutResult>("toggleLayout", { ...input });
    },
    pinLayoutWindow(input) {
      return operation<PinLayoutWindowResult>("pinLayoutWindow", { ...input });
    },
    addLayoutTarget(input) {
      return operation<AddLayoutTargetResult>("addLayoutTarget", { ...input });
    },
    updateLayout(input) {
      return operation<UpdateLayoutResult>("updateLayout", { ...input });
    },
    toggleModeCollapse(input) {
      return operation<ToggleModeCollapseResult>("toggleModeCollapse", { ...input });
    },
    closeAllWindows() {
      return operation<CommandReceipt>("closeAllWindows", {});
    },
    listWindows() {
      return operation<WindowInventory>("listWindows", {});
    },
    minimizeWindow(input) {
      return operation<WindowActionResult>("minimizeWindow", { ...input });
    },
    surfaceWindow(input) {
      return operation<WindowActionResult>("surfaceWindow", { ...input });
    },
    closeWindow(input) {
      return operation<WindowActionResult>("closeWindow", { ...input });
    },
    captureLayout() {
      return operation<CaptureLayoutResult>("captureLayout", {});
    },
    subscribe(listener): Unsubscribe {
      listeners.add(listener);
      // Deliver any capability replay that arrived before the first subscriber.
      while (bufferedCapabilityEvents.length > 0) {
        const event = bufferedCapabilityEvents.shift();
        if (event) {
          listener(event);
        }
      }
      return () => {
        listeners.delete(listener);
      };
    }
  };
}
