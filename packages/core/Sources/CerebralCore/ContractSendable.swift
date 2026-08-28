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
extension CerebralContracts.Category: @unchecked Sendable {}
extension StatusElement: @unchecked Sendable {}
extension CerebralHelmToolDescriptor: @unchecked Sendable {}
extension CerebralHelmWorkflowDefinition: @unchecked Sendable {}
extension CerebralHelmStructuredError: @unchecked Sendable {}
extension DataLeavingDevice: @unchecked Sendable {}
extension Reversibility: @unchecked Sendable {}

// The report document graph (NIC-250). The passive-tier composer decodes a model's answer into
// these and hands the result back across a suspension point, so the whole graph has to cross a
// concurrency domain — including the block kinds' enums, which are the vocabulary that makes
// decoding a validation step rather than a formality.
//
// `@unchecked` earns its keep on the action types rather than merely working around file
// placement: their `params` is `[String: JSONAny]?`, and `JSONAny` is a class boxing `Any`. It is
// written once by the decoder and never mutated, and the values behind it come from a model's JSON
// — strings, numbers, booleans, arrays, objects — so nothing shared here is a reference type with
// mutable state. `CerebralHelmToolDescriptor` above carries the same box for the same reason.
//
// These names are codegen's, not authored, and quicktype has already renamed types in this file
// once. If a regenerate breaks this list, the fix is to follow the rename here — not to widen the
// conformance to something that no longer means what it says.
extension CerebralHelmReportDocument: @unchecked Sendable {}
extension Block: @unchecked Sendable {}
extension BlockKind: @unchecked Sendable {}
extension GreetingSize: @unchecked Sendable {}
extension LineEmphasis: @unchecked Sendable {}
extension MetricTone: @unchecked Sendable {}
extension ListItem: @unchecked Sendable {}
extension ListItemReportAction: @unchecked Sendable {}
extension PurpleReportAction: @unchecked Sendable {}
extension ReportActionElement: @unchecked Sendable {}
extension ScoreboardSide: @unchecked Sendable {}
extension LeaderboardRow: @unchecked Sendable {}

// The composer's configuration (NIC-252), for the same reason: the composer holds it and is itself
// `Sendable`.
extension CerebralHelmModelComposerCatalog: @unchecked Sendable {}
extension ComposerReport: @unchecked Sendable {}
extension CerebralHelmComposerActionCatalog: @unchecked Sendable {}
extension ModelProfileID: @unchecked Sendable {}
