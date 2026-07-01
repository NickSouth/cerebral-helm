import type { WidgetData } from "../widgets/widgetData";

export type DashboardMode = "Executive" | "Developer" | "School" | "Entertainment";

/** The degraded-aware state a region (or metric channel) can be in. */
export type RegionState = "ready" | "empty" | "stale" | "unavailable";

export type DashboardUiState =
  | "loading"
  | "empty"
  | "stale"
  | "unavailable"
  | "offline"
  | "error"
  | "confirmation"
  | "success"
  | "cancelled"
  | "ready";

/** Heimlich consciousness states (design spec §5.8); `listening` is wired but voice-deferred. */
export type HeimlichState =
  | "idle"
  | "listening"
  | "thinking"
  | "acting"
  | "awaiting_confirmation"
  | "success"
  | "error"
  | "offline";

export interface ConversationMessage {
  readonly id: string;
  readonly role: "user" | "heimlich";
  readonly text: string;
}

/** The in-conversation docked bottom input — distinct from the persistent top Ask Heimlich launcher. */
export interface ConversationInput {
  readonly draft?: string;
  readonly placeholder: string;
}

export interface HeimlichConversation {
  readonly open: boolean;
  readonly transcript: readonly ConversationMessage[];
  readonly input: ConversationInput;
}

/** The center surface; always present — chat is a translucent overlay, never a replacement (§5.7). */
export interface HeimlichSurface {
  readonly state: HeimlichState;
  readonly conversation: HeimlichConversation;
}

/**
 * A resolved mode view as the bridge delivers it (not the raw config file). All four
 * are shipped eagerly in the bootstrap state so a mode switch re-themes instantly.
 */
export interface ModeView {
  readonly id: string;
  readonly label: string;
  readonly theme: { readonly accentPrimary: string; readonly accentSecondary: string };
  readonly quickApps: readonly string[];
  /** Exactly 8 ordered slots; null = an unconfigured slot (honest disabled placeholder). */
  readonly quickActions: readonly (string | null)[];
  readonly widgets: { readonly left: string; readonly right: string };
  readonly greeting?: {
    readonly persona: string;
    readonly directive?: string;
    readonly fallback: string;
    /** User-facing tagline shown under the greeting (design reference §5.7). */
    readonly subtitle?: string;
  };
  readonly calendarProfile?: string;
  readonly newsProfile?: string;
}

export interface AgentSummary {
  readonly id: string;
  readonly label: string;
  readonly summary: string;
  /** Configured availability flag (agent config `status`), not the runtime dashboard state. */
  readonly availability: "mock" | "disabled" | "unavailable" | "enabled";
  /** Runtime dashboard status (design spec §5.10); event-driven, idle in bootstrap. */
  readonly activity: "idle" | "waiting" | "thinking" | "ready";
}

export interface ScheduleItem {
  readonly id: string;
  readonly title: string;
  readonly start?: string;
  readonly kind: "today" | "tonight";
}

export interface ScheduleRegion {
  readonly state: RegionState;
  readonly items: readonly ScheduleItem[];
  readonly emptyMessage?: string;
}

export interface MetricChannel {
  readonly state: RegionState;
  readonly label: string;
}

/** Network channel with optional up/down throughput split (mirrors DashboardNetworkChannel). */
export interface NetworkChannel extends MetricChannel {
  readonly uploadMbps?: number;
  readonly downloadMbps?: number;
}

/** Battery channel with an optional charge percentage (Mac-only capability; mocked pre-Mac). */
export interface BatteryChannel extends MetricChannel {
  readonly percent?: number;
}

/** Weather channel for the bottom bar (mirrors DashboardWeatherChannel). */
export interface WeatherChannel extends MetricChannel {
  readonly temperatureF?: number;
  readonly condition?: string;
}

export interface SystemHealthRegion {
  readonly state: RegionState;
  readonly cpuPercent?: number;
  readonly memoryPercent?: number;
  readonly network?: NetworkChannel;
  readonly battery: BatteryChannel;
}

export interface NewsHeadline {
  readonly id: string;
  readonly title: string;
  readonly source: string;
}

export interface NewsRegion {
  readonly state: RegionState;
  readonly headlines: readonly NewsHeadline[];
  readonly emptyMessage?: string;
}

export interface DashboardRegions {
  readonly schedule: ScheduleRegion;
  readonly systemHealth: SystemHealthRegion;
  readonly news: NewsRegion;
  readonly widgets: { readonly left: WidgetData; readonly right: WidgetData };
}

export interface DashboardBootstrapState {
  readonly mode: DashboardMode;
  readonly project: string;
  readonly summary: string;
  readonly commandsToday: number;
  readonly pendingConfirmations: number;
  /** Ambient weather for the bottom bar; optional (Mac-only capability, mocked pre-Mac). */
  readonly weather?: WeatherChannel;
  readonly uiState: DashboardUiState;
  /** The center surface — Heimlich's consciousness — present in every mode; never replaced. */
  readonly heimlich: HeimlichSurface;
  /** The agent whose right-column-width workspace panel is open, or null. Defaults to null. */
  readonly expandedAgent: string | null;
  /** All four resolved mode views, eager (animated, no-flash mode switch). */
  readonly modes: readonly ModeView[];
  /** The fixed global agent roster, identical in every mode. */
  readonly agents: readonly AgentSummary[];
  /** The active mode's region data; degraded-aware. */
  readonly regions: DashboardRegions;
}

/**
 * The eager, mode-independent config bundle (all four mode views + the fixed agent
 * roster). The bridge resolves it once; the mock composes it with a per-state snapshot
 * to form a full bootstrap state. NIC-52 makes this event-driven without changing
 * consumers.
 */
export interface DashboardConfigBundle {
  readonly modes: readonly ModeView[];
  readonly agents: readonly AgentSummary[];
}

/**
 * The per-state slice the canonical-states catalog carries: a bootstrap state minus the
 * eager config bundle. Composed with a DashboardConfigBundle into a DashboardBootstrapState.
 */
export type DashboardStateSnapshot = Omit<DashboardBootstrapState, "modes" | "agents">;

// --- Confirmation disclosure (mirror of packages/contracts/schemas/tools/confirmation-disclosure.schema.json) ---

/** Risk classes — owned by deterministic policy (ADR-003); the UI renders, never classifies. */
export type ConfirmationRisk =
  | "read_only"
  | "local_write"
  | "external_write"
  | "destructive"
  | "shell"
  | "financial"
  | "purchase_or_booking";

export type ConfirmationDataLeavingDevice = "none" | "metadata_only" | "content" | "unknown";
export type ConfirmationReversibility = "reversible" | "partially_reversible" | "not_reversible" | "unknown";

export interface ConfirmationTool {
  readonly id: string;
  readonly version: string;
  readonly purpose: string;
}

export interface ConfirmationArgument {
  readonly name: string;
  readonly value: string;
  /** Sensitive values are masked in the disclosure, never shown verbatim. */
  readonly sensitive: boolean;
}

export interface ConfirmationChoice {
  readonly label: string;
}

export interface ConfirmationChoices {
  readonly approve: ConfirmationChoice;
  readonly review: ConfirmationChoice;
  readonly cancel: ConfirmationChoice;
  /** Approve is NEVER the default-focused control — policy constrains this to review/cancel. */
  readonly defaultFocusedChoice: "review" | "cancel";
}

export interface ConfirmationInvalidation {
  readonly expires: boolean;
  readonly invalidAfterPlanChange: boolean;
  readonly singleUseToken: boolean;
}

/**
 * The policy-owned confirmation disclosure. Delivered to the UI at runtime via the
 * `confirmation.changed` event (never part of the static bootstrap config). The dashboard
 * renders every field verbatim and submits a decision via `decideConfirmation`; it never
 * classifies risk, bypasses policy, or executes the underlying action (design spec §9).
 */
export interface ConfirmationDisclosure {
  readonly schemaVersion: string;
  readonly id: string;
  readonly commandId: string;
  readonly planHash: string;
  readonly actionSummary: string;
  readonly tool: ConfirmationTool;
  readonly risk: ConfirmationRisk;
  readonly destination: string | null;
  readonly arguments: readonly ConfirmationArgument[];
  readonly dataLeavingDevice: ConfirmationDataLeavingDevice;
  readonly accountOrService: string | null;
  readonly reversibility: ConfirmationReversibility;
  readonly policyReason: string;
  readonly choices: ConfirmationChoices;
  readonly expiresAt: string;
  readonly invalidation: ConfirmationInvalidation;
  readonly executionNotice: string;
}
