// Resolving a configured runtime id to the adapter that speaks it (NIC-228).
#if canImport(AppKit)
import Foundation
import CerebralCore

/// Builds the ``ModelProvider`` for a configured runtime id.
///
/// The port names the **runtime**, not just the model, because the difference that matters most —
/// whether an invalid document is impossible or merely unlikely — is a property of the runtime
/// (ADR-009). This is where that name becomes a concrete, and it is the first thing in the product
/// to need one: phase 0 shipped both adapters with nothing calling either.
///
/// Unknown ids return nil rather than falling back to a default. A configuration naming a runtime
/// this build cannot serve is a mistake, and quietly serving it with a different one would produce
/// a working brief composed by something other than what the configuration says.
public enum ModelProviderFactory {
    public static func provider(for runtime: ModelRuntimeIdentifier) -> (any ModelProvider)? {
        switch runtime {
        case .ollama:
            return OllamaModelProvider()
        case .llamaCPP:
            // Reports `enforcesResponseSchema: true`, and has earned it — measured 0 invalid
            // documents in 18 compositions where Ollama produced 6. Reachable by repointing a
            // profile in `config/models/profiles.json`; not the default, because it needs a
            // `llama-server` process the app does not own, and it composed ~40% slower.
            return LlamaCPPModelProvider()
        default:
            // `mlx` and anything added to configuration later. Named explicitly in the switch above
            // when an adapter exists; nil until then.
            return nil
        }
    }
}
#endif
