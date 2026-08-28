import Foundation

/// Which project's sprint the daily brief reports on (owner decision, 2026-08-26).
///
/// **The highest-`importance` active project that declares a `linear_project`.** No new concept and
/// no new configuration: `importance` already orders the projects rail, and `linear_project` already
/// links a folder to Linear. A brief that reported every project's sprint would be a status page,
/// and one that asked which to use would be a prompt.
///
/// Pure and portable, and kept out of the app-layer concrete on purpose: this is a rule, and a rule
/// living in `apps/mac` would be covered only by the macOS test job and by no CI job at all.
public enum SprintProjectResolver {
    /// One resolved project: the folder it came from, and the Linear project it names.
    public struct Resolved: Equatable, Sendable {
        public let project: ProjectSummary
        /// As the descriptor spells it. Linear matches case-insensitively and echoes its own
        /// canonical form back, which is what confirms the link rather than assuming it.
        public let linearProject: String

        public init(project: ProjectSummary, linearProject: String) {
            self.project = project
            self.linearProject = linearProject
        }
    }

    /// The first project in `projects` that declares a Linear project, or nil when none does.
    ///
    /// `projects` is expected in the order ``ActiveProjectsProvider`` already returns — declared
    /// importance first and descending, then most-recently-active. That ordering is not recomputed
    /// here: two places sorting the same list by the same rule is one place too many, and the rail
    /// and the brief agreeing about which project matters most is the point.
    ///
    /// `linearProject` is injected rather than read, because reading it means touching the
    /// filesystem and this stays pure. The app supplies `ProjectDescriptor.read`.
    public static func resolve(
        projects: [ProjectSummary],
        linearProject: (ProjectSummary) -> String?
    ) -> Resolved? {
        for project in projects {
            // Only a project with a descriptor can declare a link, and asking about one without is
            // a filesystem read that can only answer nil.
            guard project.hasDescriptor else { continue }
            guard let name = linearProject(project)?.trimmingCharacters(in: .whitespaces),
                  !name.isEmpty
            else { continue }
            return Resolved(project: project, linearProject: name)
        }
        return nil
    }
}
