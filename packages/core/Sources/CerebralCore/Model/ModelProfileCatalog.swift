import Foundation
import CerebralContracts

/// The capability profile product logic asks for (ADR-009, and the tech stack's Model Profiles).
///
/// Callers name a profile, never a model. The default model changed once during planning already,
/// and the standing rule is that no named local model becomes an architectural dependency —
/// profiles survive that churn, model ids do not.
public enum ModelCapabilityProfile: String, Equatable, Sendable, CaseIterable {
    /// Classification, routing, lightweight extraction, simple drafts.
    case fast
    /// Normal reasoning, retrieval synthesis, bounded multi-tool work.
    case balanced
    /// Ambiguous planning, complex research, high-value reasoning. The one place deliberation
    /// is expected to be on.
    case deep
    /// Not a capability but a policy: work that must never leave this machine, even if a cloud
    /// escape hatch is later enabled.
    case local
}

/// One profile resolved to everything needed to serve it.
public struct ModelProfileResolution: Equatable, Sendable {
    public let profile: ModelCapabilityProfile
    public let modelID: String
    public let runtime: ModelRuntimeIdentifier
    public let contextTokens: Int
    public let residency: ModelResidency
    public let thinking: Bool
    public let timeout: Duration
    /// Advisory estimate of this model's resident footprint, when the catalog states one.
    public let residentGigabytes: Double?

    public init(
        profile: ModelCapabilityProfile,
        modelID: String,
        runtime: ModelRuntimeIdentifier,
        contextTokens: Int,
        residency: ModelResidency,
        thinking: Bool,
        timeout: Duration,
        residentGigabytes: Double? = nil
    ) {
        self.profile = profile
        self.modelID = modelID
        self.runtime = runtime
        self.contextTokens = contextTokens
        self.residency = residency
        self.thinking = thinking
        self.timeout = timeout
        self.residentGigabytes = residentGigabytes
    }

    /// The generation options this profile implies. `responseFormat` and `temperature` stay with
    /// the caller — they are properties of the *request*, not of the profile — while the model,
    /// context cap, residency, deliberation and budget all come from configuration.
    public func options(
        temperature: Double = 0,
        maxOutputTokens: Int? = nil,
        responseFormat: ModelResponseFormat = .text
    ) -> ModelGenerationOptions {
        ModelGenerationOptions(
            modelID: modelID,
            contextTokens: contextTokens,
            temperature: temperature,
            maxOutputTokens: maxOutputTokens,
            thinking: thinking,
            responseFormat: responseFormat,
            residency: residency,
            timeout: timeout
        )
    }
}

/// Resolves a capability profile to a model, a runtime, a context cap and a residency (NIC-243).
///
/// Built from `config/models/profiles.json`. The catalog is **optional**: with no such file the app
/// runs exactly as it does today, because no model is required for the product to work.
public struct ModelProfileCatalog: Equatable, Sendable {
    /// Advisory only, never enforced. How much model weight this machine holds before it swaps.
    public let residentBudgetGigabytes: Double?
    private let resolutions: [ModelCapabilityProfile: ModelProfileResolution]

    public init(residentBudgetGigabytes: Double? = nil, resolutions: [ModelProfileResolution]) {
        self.residentBudgetGigabytes = residentBudgetGigabytes
        self.resolutions = Dictionary(
            resolutions.map { ($0.profile, $0) },
            // A duplicate profile id is rejected by validation before it reaches here; last-wins
            // keeps this initialiser total rather than trapping on data it does not police.
            uniquingKeysWith: { _, last in last }
        )
    }

    /// Builds the catalog from validated configuration.
    ///
    /// The default timeout is applied here rather than in the schema so the number lives with the
    /// code that uses it: an absent `timeoutSeconds` is 120 seconds.
    public init(_ config: CerebralHelmModelProfileCatalog) {
        self.init(
            residentBudgetGigabytes: config.residentBudgetGigabytes,
            resolutions: config.modelProfiles.map { profile in
                ModelProfileResolution(
                    profile: ModelCapabilityProfile(profile.id),
                    modelID: profile.modelID,
                    runtime: ModelRuntimeIdentifier(rawValue: profile.runtimeID),
                    contextTokens: profile.contextTokens,
                    residency: ModelResidency(profile.residency, idleSeconds: profile.residencyIdleSeconds),
                    thinking: profile.thinking,
                    timeout: .seconds(profile.timeoutSeconds ?? 120),
                    residentGigabytes: profile.residentGigabytes
                )
            }
        )
    }

    /// The resolution for `profile`, or nil when the catalog does not configure it.
    ///
    /// Nil is a real answer, not a failure: a machine may reasonably configure `balanced` and
    /// nothing else, and a caller that needs `deep` should say so honestly rather than silently
    /// fall back to a model chosen for a different job.
    public func resolve(_ profile: ModelCapabilityProfile) -> ModelProfileResolution? {
        resolutions[profile]
    }

    public var configuredProfiles: [ModelCapabilityProfile] {
        ModelCapabilityProfile.allCases.filter { resolutions[$0] != nil }
    }

    /// Advisory: the resident weight this catalog would pin, counted **once per distinct model
    /// id**, because four profiles sharing one model pin one model, not four.
    ///
    /// Nil when no pinned profile states a footprint. Nothing acts on this — the budget is
    /// documented, not enforced (ADR-009) — but it is what a future check would measure.
    public var pinnedResidentGigabytes: Double? {
        var seen: Set<String> = []
        var total: Double = 0
        var stated = false
        for resolution in resolutions.values where resolution.residency == .pinned {
            guard seen.insert(resolution.modelID).inserted else { continue }
            if let gigabytes = resolution.residentGigabytes {
                total += gigabytes
                stated = true
            }
        }
        return stated ? total : nil
    }

    /// Whether the pinned weight exceeds the stated budget. Advisory; no caller is blocked by it.
    public var exceedsResidentBudget: Bool {
        guard let budget = residentBudgetGigabytes, let pinned = pinnedResidentGigabytes else {
            return false
        }
        return pinned > budget
    }
}

private extension ModelCapabilityProfile {
    init(_ id: ModelProfileID) {
        switch id {
        case .fast: self = .fast
        case .balanced: self = .balanced
        case .deep: self = .deep
        case .local: self = .local
        }
    }
}

private extension ModelResidency {
    /// Maps the flat config pair (`residency` + `residencyIdleSeconds`) onto the port's enum.
    ///
    /// A `bounded` profile with no idle window is rejected by validation, so the fallback here is
    /// unreachable in a validated catalog; it is Ollama's own five-minute default rather than a
    /// guess, so even the unreachable path is honest.
    init(_ residency: Residency, idleSeconds: Int?) {
        switch residency {
        case .pinned: self = .pinned
        case .evictAfterUse: self = .evictAfterUse
        case .bounded: self = .bounded(.seconds(idleSeconds ?? 300))
        }
    }
}
