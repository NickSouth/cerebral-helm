import Foundation
import CerebralCore

/// The reusable health-check shapes (quick actions phase 5).
///
/// Six parameterized types cover the whole inventory, so adding a check is a line of composition
/// rather than a new class. That matters for the surface's own honesty: the checks are supposed to
/// track a moving world, and a list that is expensive to extend stops being extended.
///
/// None of them writes anything, and none spends a quota. Where a provider's budget is small
/// enough that a probe would matter, the check verifies as far as it can for free and *says* that
/// — see ``SecretHealthCheck``'s `probe`.

// MARK: - Permissions

/// A macOS permission, read without prompting.
///
/// `notRequired` passes and says so: "no platform gate exists" is a different fact from "the user
/// granted it", and collapsing them would make the checklist claim a grant nobody gave.
/// `notDetermined` is **not** a failure — nobody has been asked yet — so it is skipped with that
/// reason, which is also the honest state for a permission whose prompt happens at point of use.
public struct PermissionHealthCheck: HealthCheck {
    public let descriptor: HealthCheckDescriptor
    private let permissionID: String
    private let checker: any PermissionChecking
    private let remediation: String?

    public init(
        id: String,
        title: String,
        permissionID: String,
        checker: any PermissionChecking,
        detail: String? = nil,
        remediation: String? = nil
    ) {
        self.descriptor = HealthCheckDescriptor(
            id: id, title: title, group: .permissions, detail: detail
        )
        self.permissionID = permissionID
        self.checker = checker
        self.remediation = remediation
    }

    public func run() async -> HealthCheckOutcome {
        switch checker.status(of: permissionID) {
        case .granted:
            return .passed(detail: "Granted.")
        case .notRequired:
            return .passed(detail: "No permission needed on this Mac.")
        case .denied:
            return .failed(reason: "Denied.", remediation: remediation)
        case .notDetermined:
            return .skipped(reason: "Not asked yet — macOS will prompt the first time it's needed.")
        }
    }
}

// MARK: - Credentials and integrations

/// A credential, and optionally a live probe of the service behind it.
///
/// **Unbound is skipped, never failed.** An integration the user never set up is not broken, and a
/// checklist that reddens over things nobody asked for stops being read.
///
/// **`probe` is optional on purpose.** A provider with a small daily budget (NewsData's 200/day,
/// which this app has already exhausted once) gets no probe at all: the check confirms the key is
/// bound and says exactly that, rather than implying a live verification it deliberately did not
/// make. A generous or free endpoint gets a real probe, because "the key exists" and "the key
/// works" are very different facts and an expired token looks identical to a good one until used.
public struct SecretHealthCheck: HealthCheck {
    /// Verifies the service with the resolved secret. Returns nil on success, or the reason it
    /// failed. Non-throwing for the same reason ``HealthCheck/run()`` is.
    public typealias Probe = @Sendable (String) async -> String?

    public let descriptor: HealthCheckDescriptor
    private let reference: String
    private let secrets: any SecretStoreManaging
    private let probe: Probe?
    private let unboundReason: String
    private let remediation: String?

    public init(
        id: String,
        title: String,
        reference: String,
        secrets: any SecretStoreManaging,
        detail: String? = nil,
        unboundReason: String = "Not set up.",
        remediation: String? = nil,
        probe: Probe? = nil
    ) {
        self.descriptor = HealthCheckDescriptor(
            id: id, title: title, group: .integrations, detail: detail
        )
        self.reference = reference
        self.secrets = secrets
        self.probe = probe
        self.unboundReason = unboundReason
        self.remediation = remediation
    }

    public func run() async -> HealthCheckOutcome {
        guard let value = try? await secrets.readValue(reference: reference), !value.isEmpty else {
            return .skipped(reason: unboundReason)
        }
        guard let probe else {
            // Says precisely what was established. "Passed" on its own would invite the reader to
            // assume the service answered, which nothing here checked.
            return .passed(detail: "Key is set. Not contacted — this provider's free quota is small.")
        }
        if let failure = await probe(value) {
            return .failed(reason: failure, remediation: remediation)
        }
        return .passed(detail: "Answered.")
    }
}

/// An unauthenticated endpoint whose *shape* the app depends on.
///
/// Aimed squarely at the undocumented ones — ESPN's site API is read on the explicit understanding
/// that it can change without notice, so a check that confirms the fields are still where the
/// mapper expects is worth more than one that confirms the host is up.
public struct EndpointHealthCheck: HealthCheck {
    /// Validates the response body. Returns nil when the shape is still good, else the reason.
    public typealias Validate = @Sendable (Data) -> String?

    /// Performs the read. A closure rather than a `URLSession` because this package is portable —
    /// `URLSession` lives in a different module off Darwin — and because a check whose transport is
    /// injected can be tested without a network. `statusCode` is nil where the transport has none.
    public typealias Fetch = @Sendable (URL) async throws -> (data: Data, statusCode: Int?)

    public let descriptor: HealthCheckDescriptor
    private let url: URL
    private let fetch: Fetch
    private let validate: Validate?
    private let remediation: String?

    public init(
        id: String,
        title: String,
        url: URL,
        fetch: @escaping Fetch,
        detail: String? = nil,
        remediation: String? = nil,
        validate: Validate? = nil
    ) {
        self.descriptor = HealthCheckDescriptor(
            id: id, title: title, group: .integrations, detail: detail
        )
        self.url = url
        self.fetch = fetch
        self.validate = validate
        self.remediation = remediation
    }

    public func run() async -> HealthCheckOutcome {
        do {
            let (data, statusCode) = try await fetch(url)
            if let statusCode, !(200..<300).contains(statusCode) {
                return .failed(reason: "Returned HTTP \(statusCode).", remediation: remediation)
            }
            if let validate, let reason = validate(data) {
                // The interesting failure: reachable, and no longer the shape we read.
                return .failed(reason: reason, remediation: remediation)
            }
            return .passed(detail: "Answered, and still the shape we read.")
        } catch is CancellationError {
            return .failed(reason: "Cancelled.", remediation: nil)
        } catch {
            return .failed(reason: error.localizedDescription, remediation: remediation)
        }
    }
}

// MARK: - Local state

/// A folder the app depends on, and whether it can be written.
///
/// Renaming a folder in Finder is the cheapest way to break the app from outside the code, and
/// nothing else notices until a write fails at the worst moment.
public struct PathHealthCheck: HealthCheck {
    public let descriptor: HealthCheckDescriptor
    private let path: String
    private let requiresWrite: Bool
    private let remediation: String?

    public init(
        id: String,
        title: String,
        path: String,
        requiresWrite: Bool,
        detail: String? = nil,
        remediation: String? = nil
    ) {
        self.descriptor = HealthCheckDescriptor(id: id, title: title, group: .storage, detail: detail)
        self.path = path
        self.requiresWrite = requiresWrite
        self.remediation = remediation
    }

    public func run() async -> HealthCheckOutcome {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return .failed(reason: "Not found at \(path).", remediation: remediation)
        }
        guard isDirectory.boolValue else {
            return .failed(reason: "\(path) is a file, not a folder.", remediation: remediation)
        }
        if requiresWrite, !FileManager.default.isWritableFile(atPath: path) {
            return .failed(reason: "Not writable.", remediation: remediation)
        }
        return .passed(detail: path)
    }
}

/// Anything answerable with a closure — the escape hatch for a check that is one line of platform
/// code and does not deserve a type.
///
/// Used for the macOS surfaces that are a single query: whether an app is installed, whether a URL
/// scheme has a handler, how stale a scraped feed is.
public struct InlineHealthCheck: HealthCheck {
    public let descriptor: HealthCheckDescriptor
    private let body: @Sendable () async -> HealthCheckOutcome

    public init(
        id: String,
        title: String,
        group: HealthCheckGroup,
        detail: String? = nil,
        body: @escaping @Sendable () async -> HealthCheckOutcome
    ) {
        self.descriptor = HealthCheckDescriptor(id: id, title: title, group: group, detail: detail)
        self.body = body
    }

    public func run() async -> HealthCheckOutcome { await body() }
}

/// A fixed outcome, for tests and for a host that cannot run a check at all.
public struct StaticHealthCheck: HealthCheck {
    public let descriptor: HealthCheckDescriptor
    private let outcome: HealthCheckOutcome

    public init(descriptor: HealthCheckDescriptor, outcome: HealthCheckOutcome) {
        self.descriptor = descriptor
        self.outcome = outcome
    }

    public func run() async -> HealthCheckOutcome { outcome }
}
