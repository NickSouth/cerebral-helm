import Foundation

/// Who authored one turn of a model conversation (NIC-241).
///
/// Deliberately **not** named `ModelRole`: "role" in this codebase means a capability profile
/// (`fast` / `balanced` / `deep` / `local`, ADR-009), which is a configuration key, not a
/// conversational position. Keeping the two words apart stops a future reader from wiring a
/// profile into a message.
public enum ModelMessageRole: String, Equatable, Sendable, Codable {
    case system
    case user
    case assistant
    /// The result of a tool the model asked for. Nothing in this package *invokes* a tool — the
    /// generic invocation path is phase 2 (NIC-232) — but the transcript shape has to exist for a
    /// caller to feed a result back, and a runtime that never sees `tool` turns re-issues calls it
    /// has no record of making.
    case tool
}

/// One turn in a model conversation. Provider-neutral: a concrete adapter maps this onto whatever
/// its runtime's wire format happens to be, which is one of the three axes ADR-009 puts behind the
/// port precisely because it churns per model family.
public struct ModelMessage: Equatable, Sendable {
    public let role: ModelMessageRole
    /// The turn's text. For a `tool` turn this is the tool's rendered result.
    public let content: String
    /// The calls an `assistant` turn asked for, in the order the model emitted them. Empty for
    /// every other role.
    public let toolCalls: [ModelToolCall]
    /// For a `tool` turn, the id of the call being answered, when the runtime issued one. Optional
    /// because not every runtime assigns call ids — Ollama does not — and inventing one would be a
    /// fabrication the adapter cannot honour.
    public let toolCallID: String?
    /// For a `tool` turn, the name of the tool that produced this result.
    public let toolName: String?

    public init(
        role: ModelMessageRole,
        content: String,
        toolCalls: [ModelToolCall] = [],
        toolCallID: String? = nil,
        toolName: String? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.toolName = toolName
    }

    public static func system(_ content: String) -> ModelMessage {
        ModelMessage(role: .system, content: content)
    }

    public static func user(_ content: String) -> ModelMessage {
        ModelMessage(role: .user, content: content)
    }

    public static func assistant(_ content: String, toolCalls: [ModelToolCall] = []) -> ModelMessage {
        ModelMessage(role: .assistant, content: content, toolCalls: toolCalls)
    }

    public static func toolResult(
        _ content: String,
        toolName: String,
        toolCallID: String? = nil
    ) -> ModelMessage {
        ModelMessage(
            role: .tool,
            content: content,
            toolCallID: toolCallID,
            toolName: toolName
        )
    }
}

/// A model's request to invoke one tool, normalised out of whatever the runtime emitted.
///
/// This is the *proposal*, never the invocation: risk classification and confirmation stay
/// deterministic and outside the model (ADR-003, ADR-009). Arguments arrive as a structural
/// ``JSONValue`` rather than a typed payload because the port cannot know the tool — validation
/// against the tool's `inputSchema` belongs to the registry, and constraining generation to that
/// schema is NIC-249.
public struct ModelToolCall: Equatable, Sendable {
    /// The runtime's id for this call, when it issues one. Ollama does not.
    public let id: String?
    /// The registered tool id the model named. Not validated here — an unknown name is a finding
    /// for the caller, not a parse failure.
    public let name: String
    /// The arguments as emitted. Structural, and never assumed schema-valid: Ollama's structured
    /// output does not enforce leaf types (ADR-009 Context), so a `count` can arrive as `0` where
    /// a string was required.
    public let arguments: JSONValue

    public init(id: String? = nil, name: String, arguments: JSONValue) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// One tool as described *to* a model: the manifest entry, not the registered tool.
///
/// Phase 2 (NIC-266) projects the authoritative descriptors in `config/tools/descriptors/` into
/// these. Two fields are deliberately absent and must stay absent: risk class and confirmation
/// policy. Telling a model an action is destructive invites it to reason about its own permissions,
/// and that decision does not belong to it (ADR-003, and decision 18 of the LLM decision log).
public struct ModelToolDefinition: Equatable, Sendable {
    public let name: String
    public let description: String
    /// The tool's JSON Schema for arguments, structurally.
    public let parameters: JSONValue

    public init(name: String, description: String, parameters: JSONValue) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}
