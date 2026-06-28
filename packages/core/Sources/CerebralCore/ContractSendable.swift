import CerebralContracts

// The generated contract bindings are plain value types, but quicktype does not
// emit `Sendable` conformances. The command spine — and the actor-based command
// bus in NIC-25 — needs these statuses to cross concurrency domains. Declare the
// conformance here as a bridge until scripts/generate-contracts.mjs emits it.
//
// These are `String`-raw enums with no associated values and are genuinely
// `Sendable`. `@unchecked` is required only because the conformance lives in a
// different source file than the generated declaration; a checked conformance
// would have to sit in the generated file. If the generator later emits its own
// `Sendable` conformances, these lines become duplicates and should be removed.
extension PreviousStatus: @unchecked Sendable {}
extension CerebralHelmCommandEnvelopeSource: @unchecked Sendable {}
extension Risk: @unchecked Sendable {}
extension RuntimeRiskPolicy: @unchecked Sendable {}
extension Category: @unchecked Sendable {}
extension StatusElement: @unchecked Sendable {}
extension CerebralHelmToolDescriptor: @unchecked Sendable {}
extension CerebralHelmWorkflowDefinition: @unchecked Sendable {}
extension CerebralHelmStructuredError: @unchecked Sendable {}
extension DataLeavingDevice: @unchecked Sendable {}
extension Reversibility: @unchecked Sendable {}
