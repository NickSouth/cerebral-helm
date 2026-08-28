// The daily brief's sprint, read from Linear (NIC-228).
#if canImport(AppKit)
import Foundation
import CerebralCore

/// Resolves which project the brief reports on, then reads that project's active cycle.
///
/// Thin glue by design. The *rule* — highest-`importance` project declaring a `linear_project` —
/// lives in ``SprintProjectResolver`` in the portable core, where it is covered by `swift test` on
/// every platform; this file only supplies the two things that cannot be portable: a filesystem
/// read for the descriptors and an HTTP call to Linear.
///
/// It reuses ``LinearProjectCycleProviding`` rather than issuing its own query, so the brief and the
/// projects widget cannot disagree about what is in the cycle. The projection down to ``Sprint``
/// deliberately drops issue URLs, state colours, sort order and avatar initials: a brief has no use
/// for them, and every field withheld is one a model cannot misread.
public struct LinearSprintProvider: SprintProvider {
    private let projects: any ActiveProjectsProvider
    private let cycles: any LinearProjectCycleProviding
    private let linearProject: @Sendable (ProjectSummary) -> String?

    public init(
        projects: any ActiveProjectsProvider,
        cycles: any LinearProjectCycleProviding,
        // Injected so the resolver stays pure and this stays testable without a projects root on
        // disk. The default is the real descriptor read.
        linearProject: (@Sendable (ProjectSummary) -> String?)? = nil
    ) {
        self.projects = projects
        self.cycles = cycles
        self.linearProject = linearProject ?? { summary in
            ProjectDescriptor.read(projectPath: summary.path)?.linearProject
        }
    }

    public func currentSprint() async throws -> Sprint {
        let summaries: [ProjectSummary]
        do {
            summaries = try projects.activeProjects()
        } catch {
            // An unreadable projects root is not a Linear problem, and saying so keeps the reader
            // from re-pasting an API key that was never the issue.
            throw SprintError.unavailable("The projects folder couldn\u{2019}t be read.")
        }

        guard let resolved = SprintProjectResolver.resolve(
            projects: summaries, linearProject: linearProject
        ) else {
            throw SprintError.noLinkedProject
        }

        let cycle: LinearProjectCycle
        do {
            cycle = try await cycles.projectCycle(named: resolved.linearProject)
        } catch LinearAPIError.credentialsMissing {
            throw SprintError.credentialsMissing
        } catch LinearAPIError.unauthorized {
            throw SprintError.unavailable("Linear rejected the stored API key.")
        } catch LinearAPIError.rateLimited {
            throw SprintError.unavailable("Linear is rate-limiting requests right now.")
        } catch {
            throw SprintError.unavailable("Linear couldn\u{2019}t be reached.")
        }

        // A name Linear has no project for returns zero issues, which is byte-identical to a
        // correctly-linked project with an empty cycle. `matchedProject` is the only thing that
        // separates them, which is why the widget carries it and why the brief must not skip it.
        guard let matched = cycle.matchedProject else {
            throw SprintError.projectNotFound(resolved.linearProject)
        }

        return Sprint(
            projectName: matched,
            cycle: cycle.cycle.map {
                SprintCycle(number: $0.number, name: $0.name, startsAt: $0.startsAt, endsAt: $0.endsAt)
            },
            issues: cycle.issues.map {
                SprintIssue(
                    identifier: $0.identifier,
                    title: $0.title,
                    stateName: $0.state.name,
                    // Linear's `type`, not its `name`: the type is a fixed vocabulary and survives
                    // the user renaming a column, which the name does not.
                    state: SprintIssueState(linearType: $0.state.type),
                    priority: $0.priority,
                    estimate: $0.estimate,
                    labels: $0.labels
                )
            },
            truncated: cycle.truncated
        )
    }
}
#endif
