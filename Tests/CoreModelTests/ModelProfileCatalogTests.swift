import Foundation
import Testing

import CerebralCore

/// NIC-243: resolving a capability profile to a model, a context cap and a residency.
///
/// Callers name a profile and get everything else from configuration — that is the whole point,
/// because the default model has already changed once and will change again.

private func resolution(
    _ profile: ModelCapabilityProfile,
    modelID: String = "qwen3.6:35b-mlx",
    residency: ModelResidency = .pinned,
    contextTokens: Int = 16_384,
    thinking: Bool = false,
    timeout: Duration = .seconds(120),
    residentGigabytes: Double? = nil
) -> ModelProfileResolution {
    ModelProfileResolution(
        profile: profile,
        modelID: modelID,
        runtime: .ollama,
        contextTokens: contextTokens,
        residency: residency,
        thinking: thinking,
        timeout: timeout,
        residentGigabytes: residentGigabytes
    )
}

@Test("a resolved profile supplies the model, cap, residency and budget; the caller supplies the rest")
func profileProducesGenerationOptions() {
    let catalog = ModelProfileCatalog(resolutions: [
        resolution(.deep, residency: .evictAfterUse, contextTokens: 32_768, thinking: true, timeout: .seconds(600))
    ])

    let options = catalog.resolve(.deep)!.options(temperature: 0.4, responseFormat: .jsonSchema(.object([:])))

    // From configuration.
    #expect(options.modelID == "qwen3.6:35b-mlx")
    #expect(options.contextTokens == 32_768)
    #expect(options.residency == .evictAfterUse)
    #expect(options.thinking)
    #expect(options.timeout == .seconds(600))
    // From the caller — properties of the request, not of the profile.
    #expect(options.temperature == 0.4)
    #expect(options.responseFormat == .jsonSchema(.object([:])))
}

@Test("an unconfigured profile resolves to nil rather than falling back to another model")
func unconfiguredProfileIsNil() {
    let catalog = ModelProfileCatalog(resolutions: [resolution(.balanced)])

    #expect(catalog.resolve(.balanced) != nil)
    // Silently serving `deep` work with the `fast` model would be worse than saying no.
    #expect(catalog.resolve(.deep) == nil)
    #expect(catalog.configuredProfiles == [.balanced])
}

@Test("pinned weight counts each model once, however many profiles share it")
func pinnedWeightCountsDistinctModels() {
    // The shipped shape: several profiles, one model.
    let shared = ModelProfileCatalog(residentBudgetGigabytes: 48, resolutions: [
        resolution(.fast, residency: .pinned, residentGigabytes: 21),
        resolution(.balanced, residency: .pinned, residentGigabytes: 21),
        resolution(.local, residency: .pinned, residentGigabytes: 21),
    ])
    #expect(shared.pinnedResidentGigabytes == 21)
    #expect(shared.exceedsResidentBudget == false)

    // Two genuinely different pinned models is the case that measured ~51 GB and swapped 18 GB.
    let two = ModelProfileCatalog(residentBudgetGigabytes: 48, resolutions: [
        resolution(.balanced, modelID: "qwen3.6:35b-mlx", residency: .pinned, residentGigabytes: 29),
        resolution(.deep, modelID: "muse-glimmer:30b-mlx", residency: .pinned, residentGigabytes: 22),
    ])
    #expect(two.pinnedResidentGigabytes == 51)
    #expect(two.exceedsResidentBudget)
}

@Test("weight that is not pinned is not counted, and an unstated footprint is nil not zero")
func unpinnedAndUnstatedWeight() {
    let lazy = ModelProfileCatalog(residentBudgetGigabytes: 48, resolutions: [
        resolution(.deep, residency: .evictAfterUse, residentGigabytes: 21),
        resolution(.fast, residency: .bounded(.seconds(300)), residentGigabytes: 21),
    ])
    // A specialist that unloads holds nothing against the surface someone is using.
    #expect(lazy.pinnedResidentGigabytes == nil)
    #expect(lazy.exceedsResidentBudget == false)

    let unstated = ModelProfileCatalog(residentBudgetGigabytes: 48, resolutions: [resolution(.balanced)])
    #expect(unstated.pinnedResidentGigabytes == nil)
}

@Test("the budget is advisory: exceeding it is reported, never enforced")
func budgetIsAdvisory() {
    let over = ModelProfileCatalog(residentBudgetGigabytes: 8, resolutions: [
        resolution(.balanced, residency: .pinned, residentGigabytes: 21)
    ])

    #expect(over.exceedsResidentBudget)
    // Nothing is withheld. The catalog still resolves, because ADR-009 records the budget as
    // documentation rather than a gate.
    #expect(over.resolve(.balanced)?.modelID == "qwen3.6:35b-mlx")

    // With no stated budget there is nothing to exceed.
    let noBudget = ModelProfileCatalog(resolutions: [resolution(.balanced, residentGigabytes: 999)])
    #expect(noBudget.exceedsResidentBudget == false)
}
