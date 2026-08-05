import Foundation
import Testing

import CerebralCore
import CerebralTools

/// Quick actions phase 5: the reusable check shapes.
///
/// The rule under test throughout is the one that keeps the checklist worth reading — **not
/// configured is not failing** — plus the promise that a quota-limited provider is never probed.

private struct FakePermissions: PermissionChecking {
    let statuses: [String: PermissionStatus]
    func status(of permissionID: String) -> PermissionStatus {
        statuses[permissionID] ?? .notDetermined
    }
}

/// Records whether a value was ever read, so "never probed" is provable rather than assumed.
private final class FakeSecrets: SecretStoreManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]
    private var reads: [String] = []

    init(_ values: [String: String]) { self.values = values }

    func store(reference: String, value: String) async throws {}
    func delete(reference: String) async throws {}
    func readValue(reference: String) async throws -> String {
        record(reference)
        guard let value = snapshot()[reference] else {
            throw NativeCapabilityError.notFound(reference)
        }
        return value
    }

    private func record(_ reference: String) { lock.lock(); reads.append(reference); lock.unlock() }
    private func snapshot() -> [String: String] { lock.lock(); defer { lock.unlock() }; return values }
    var readReferences: [String] { lock.lock(); defer { lock.unlock() }; return reads }
}

// MARK: - Permissions

@Test("a granted permission passes, and one with no platform gate says exactly that")
func permissionCheckReportsGrants() async {
    let checker = FakePermissions(statuses: ["accessibility": .granted, "url_open": .notRequired])

    let granted = await PermissionHealthCheck(
        id: "p1", title: "Accessibility", permissionID: "accessibility", checker: checker
    ).run()
    #expect(granted == .passed(detail: "Granted."))

    // "No gate exists" and "the user granted it" are different facts; collapsing them would make
    // the checklist claim a grant nobody gave.
    let notRequired = await PermissionHealthCheck(
        id: "p2", title: "Opening URLs", permissionID: "url_open", checker: checker
    ).run()
    #expect(notRequired == .passed(detail: "No permission needed on this Mac."))
}

@Test("a denied permission fails with its fix; an unasked one is skipped, not failed")
func permissionCheckSeparatesDeniedFromUnasked() async {
    let checker = FakePermissions(statuses: ["accessibility": .denied, "contacts_read": .notDetermined])

    let denied = await PermissionHealthCheck(
        id: "p1", title: "Accessibility", permissionID: "accessibility",
        checker: checker, remediation: "System Settings → Accessibility."
    ).run()
    #expect(denied == .failed(reason: "Denied.", remediation: "System Settings → Accessibility."))

    // Nobody has been asked yet — prompting happens at point of use, so this is not a fault.
    let unasked = await PermissionHealthCheck(
        id: "p2", title: "Contacts", permissionID: "contacts_read", checker: checker
    ).run()
    guard case let .skipped(reason) = unasked else {
        Issue.record("an unasked permission must be skipped, not failed")
        return
    }
    #expect(reason.contains("Not asked yet"))
}

// MARK: - Credentials

@Test("an unbound credential is skipped with its reason — never a red row")
func secretCheckSkipsWhenUnbound() async {
    let secrets = FakeSecrets([:])
    let outcome = await SecretHealthCheck(
        id: "s1", title: "Linear", reference: "linear_api_token", secrets: secrets,
        unboundReason: "No API key — `create-ticket` is unavailable."
    ).run()

    // An integration the user never set up is not broken. A checklist that reddens over things
    // nobody asked for stops being read.
    #expect(outcome == .skipped(reason: "No API key — `create-ticket` is unavailable."))
}

@Test("a quota-limited provider is never contacted, and the row says so")
func secretCheckWithoutAProbeStatesWhatItVerified() async {
    let secrets = FakeSecrets(["newsdata_api_key": "abc123"])
    let outcome = await SecretHealthCheck(
        id: "s1", title: "NewsData", reference: "newsdata_api_key", secrets: secrets
    ).run()

    guard case let .passed(detail) = outcome else {
        Issue.record("a bound key with no probe passes")
        return
    }
    // The detail is the whole point: "passed" alone would invite the reader to assume the service
    // answered, which nothing here checked. NewsData's 200/day has been exhausted once already.
    let stated = try! #require(detail)
    #expect(stated.contains("Not contacted"))
}

@Test("a probe that reports a problem fails with the remediation attached")
func secretCheckSurfacesAProbeFailure() async {
    let secrets = FakeSecrets(["linear_api_token": "expired"])
    let outcome = await SecretHealthCheck(
        id: "s1", title: "Linear", reference: "linear_api_token", secrets: secrets,
        remediation: "Settings → Setup → Linear API key.",
        probe: { _ in "The API key was rejected." }
    ).run()

    #expect(outcome == .failed(
        reason: "The API key was rejected.", remediation: "Settings → Setup → Linear API key."
    ))
}

@Test("an unbound credential never reaches its probe — nothing is spent proving what is absent")
func secretCheckDoesNotProbeWhenUnbound() async {
    let secrets = FakeSecrets([:])
    let probed = ProbeFlag()
    _ = await SecretHealthCheck(
        id: "s1", title: "GitHub", reference: "github_api_token", secrets: secrets,
        probe: { _ in probed.fire(); return nil }
    ).run()

    #expect(!probed.fired)
}

/// A flag a `@Sendable` probe can set without a captured `var`.
private final class ProbeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func fire() { lock.lock(); value = true; lock.unlock() }
    var fired: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

// MARK: - Endpoints and paths

private let endpointURL = URL(string: "https://site.api.espn.com/scoreboard")!

@Test("an endpoint that answers in the shape we read passes")
func endpointCheckPassesOnAGoodShape() async {
    let outcome = await EndpointHealthCheck(
        id: "e1", title: "ESPN", url: endpointURL,
        fetch: { _ in (Data(#"{"events":[]}"#.utf8), 200) },
        validate: { _ in nil }
    ).run()

    #expect(outcome == .passed(detail: "Answered, and still the shape we read."))
}

@Test("a reachable endpoint whose fields moved fails on the shape, not the status")
func endpointCheckFailsOnADriftedShape() async {
    // The interesting failure for an undocumented API: 200, and no longer what the mapper reads.
    let outcome = await EndpointHealthCheck(
        id: "e1", title: "ESPN", url: endpointURL,
        fetch: { _ in (Data("{}".utf8), 200) },
        remediation: "Nothing to fix locally.",
        validate: { _ in "No `events` array." }
    ).run()

    #expect(outcome == .failed(reason: "No `events` array.", remediation: "Nothing to fix locally."))
}

@Test("a non-2xx status fails with the code, and the validator never runs")
func endpointCheckFailsOnStatus() async {
    let validated = ProbeFlag()
    let outcome = await EndpointHealthCheck(
        id: "e1", title: "ESPN", url: endpointURL,
        fetch: { _ in (Data(), 503) },
        validate: { _ in validated.fire(); return nil }
    ).run()

    #expect(outcome == .failed(reason: "Returned HTTP 503.", remediation: nil))
    // Validating a body the server never meant as an answer would report shape drift for an outage.
    #expect(!validated.fired)
}

@Test("a folder that moved fails with where it was looked for")
func pathCheckReportsAMissingFolder() async {
    let missing = FileManager.default.temporaryDirectory
        .appendingPathComponent("cerebral-absent-\(UUID().uuidString)")
    let outcome = await PathHealthCheck(
        id: "p1", title: "Knowledge root", path: missing.path, requiresWrite: true,
        remediation: "Settings → Setup → Knowledge folder."
    ).run()

    guard case let .failed(reason, remediation) = outcome else {
        Issue.record("a missing folder must fail")
        return
    }
    // Renaming a folder in Finder is the cheapest way to break the app from outside the code, and
    // the row has to name the path or the reader cannot tell what moved.
    #expect(reason.contains(missing.path))
    #expect(remediation == "Settings → Setup → Knowledge folder.")
}

@Test("a file where a folder should be is a failure, not a pass")
func pathCheckRejectsAFile() async throws {
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("cerebral-file-\(UUID().uuidString)")
    try Data("x".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }

    let outcome = await PathHealthCheck(
        id: "p1", title: "Projects root", path: file.path, requiresWrite: false
    ).run()

    guard case let .failed(reason, _) = outcome else {
        Issue.record("a file is not a folder")
        return
    }
    #expect(reason.contains("is a file"))
}

@Test("an existing writable folder passes and cites the path it checked")
func pathCheckPassesOnARealFolder() async throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("cerebral-root-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let outcome = await PathHealthCheck(
        id: "p1", title: "Knowledge root", path: folder.path, requiresWrite: true
    ).run()

    #expect(outcome == .passed(detail: folder.path))
}

@Test("an inline check reports whatever it decides, including a skip")
func inlineCheckPassesThroughItsOutcome() async {
    let outcome = await InlineHealthCheck(
        id: "i1", title: "Chrome", group: .permissions
    ) {
        .skipped(reason: "Not installed — links open in your default browser.")
    }.run()

    #expect(outcome == .skipped(reason: "Not installed — links open in your default browser."))
}
