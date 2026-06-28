import Foundation
import Testing
import CerebralCore

private func environmentRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

// MARK: - Test environment (AC-41.1)

@Test("the temporary helper yields an isolated test state root (AC-41.1)")
func temporaryHelperIsolatesTestState() throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: environmentRepositoryRoot())

    #expect(paths.environment == .test)
    #expect(paths.stateRoot.path.contains("cerebral-test-"))
    #expect(paths.eventLogPath.path.contains("cerebral-test-"))
}

@Test("a test root may sit in the repo but never resemble production")
func testEnvironmentFailsClosedOnProductionPath() {
    let root = environmentRepositoryRoot()

    #expect(throws: Never.self) {
        _ = try WorkspacePaths(
            repositoryRoot: root,
            environment: ["CEREBRAL_ENV": "test", "CEREBRAL_STATE_ROOT": ".local/test/run-1"]
        )
    }
    #expect(throws: WorkspacePathError.self) {
        _ = try WorkspacePaths(
            repositoryRoot: root,
            environment: ["CEREBRAL_ENV": "test", "CEREBRAL_STATE_ROOT": ".local/personal-production"]
        )
    }
}

// MARK: - Development environment (regression: unchanged behavior)

@Test("development stays in-repo and fails closed, with or without an explicit env")
func developmentFailsClosed() {
    let root = environmentRepositoryRoot()

    // Default (no CEREBRAL_ENV) is development and resolves the in-repo root.
    #expect(throws: Never.self) {
        let paths = try WorkspacePaths(repositoryRoot: root)
        #expect(paths.environment == .development)
        #expect(paths.stateRoot.path.contains("development"))
    }
    // Outside-repo is rejected in development.
    #expect(throws: WorkspacePathError.self) {
        _ = try WorkspacePaths(
            repositoryRoot: root,
            environment: ["CEREBRAL_ENV": "development", "CEREBRAL_STATE_ROOT": "/srv/elsewhere"]
        )
    }
}

// MARK: - Staging environment (AC-41.2)

@Test("staging requires an explicit, isolated, non-production clone root (AC-41.2)")
func stagingRequiresIsolatedCloneRoot() throws {
    let root = environmentRepositoryRoot()

    // Missing explicit root fails closed.
    #expect(throws: WorkspacePathError.self) {
        _ = try WorkspacePaths(repositoryRoot: root, environment: ["CEREBRAL_ENV": "staging"])
    }

    // An explicit, out-of-repo, sanitized clone is accepted.
    let paths = try WorkspacePaths(
        repositoryRoot: root,
        environment: ["CEREBRAL_ENV": "staging", "CEREBRAL_STATE_ROOT": "/srv/cerebral-staging-clone"]
    )
    #expect(paths.environment == .staging)
    #expect(paths.stateRoot.path.contains("cerebral-staging-clone"))

    // A production-looking staging root is rejected: a clone must be sanitized.
    #expect(throws: WorkspacePathError.self) {
        _ = try WorkspacePaths(
            repositoryRoot: root,
            environment: ["CEREBRAL_ENV": "staging", "CEREBRAL_STATE_ROOT": "/srv/cerebral-production"]
        )
    }
}

// MARK: - Production environment (AC-41.3)

@Test("production requires explicit user selection and may be a real path (AC-41.3)")
func productionRequiresExplicitSelection() throws {
    let root = environmentRepositoryRoot()

    // No implicit production root: it must be explicitly selected.
    #expect(throws: WorkspacePathError.self) {
        _ = try WorkspacePaths(repositoryRoot: root, environment: ["CEREBRAL_ENV": "production"])
    }

    // An explicit, user-selected production root may live outside the repo and
    // resemble a real production location.
    let paths = try WorkspacePaths(
        repositoryRoot: root,
        environment: ["CEREBRAL_ENV": "production", "CEREBRAL_STATE_ROOT": "/srv/cerebral-production"]
    )
    #expect(paths.environment == .production)
    #expect(paths.stateRoot.path.contains("cerebral-production"))
    #expect(paths.eventLogPath.path.contains("cerebral-production"))
}

// MARK: - Unknown environment

@Test("an unknown CEREBRAL_ENV is rejected")
func unknownEnvironmentRejected() {
    #expect(throws: WorkspacePathError.self) {
        _ = try WorkspacePaths(
            repositoryRoot: environmentRepositoryRoot(),
            environment: ["CEREBRAL_ENV": "banana"]
        )
    }
}
