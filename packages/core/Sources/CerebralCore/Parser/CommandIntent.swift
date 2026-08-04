/// A typed, model-free intent produced by the direct-command parser.
///
/// Intents describe *what* was requested; mapping them onto command-envelope
/// payloads and execution belongs to the bus and CLI (NIC-25, NIC-26).
public enum CommandIntent: Equatable, Sendable {
    case openApp(ReferenceEntry)
    case openURL(ReferenceEntry)
    case applyMode(modeId: String)
    /// Open a repository directory in the configured editor (NIC-131) — a single
    /// `project.open` tool call. The path is constrained to the projects root by the
    /// adapter, and the `local_write` risk routes it through a confirmation.
    case openProject(repoPath: String)
    case captureNote(text: String)
    case searchNotes(query: String)
    /// List the notes under the knowledge root (NIC-162) — a single read-only
    /// `note.list` tool call. Reads the Markdown itself, so a note authored
    /// outside CerebralHelm is listed before any index rebuild. `limit` caps the
    /// listing (most recently changed first); nil lists everything.
    case listNotes(limit: Int?)
    /// Read one note by its root-relative path (NIC-162) — a single read-only
    /// `note.read` tool call. The adapter refuses any path resolving outside the
    /// knowledge root.
    case readNote(path: String)
    /// Open one note in the user's Markdown editor (quick actions phase 5) — a single
    /// `note.open` tool call, addressed by the same root-relative path ``readNote`` takes.
    /// The knowledge service resolves it and refuses anything outside the knowledge root, so
    /// the path is data and never a destination.
    case openNote(path: String)
    /// Open the user's mail — the inbox, or one message by its RFC 5322 Message-ID (Gmail
    /// integration) — a single `mail.open` call. The host is fixed in the adapter; only the id
    /// varies, so a link inside a report can select a message but never a destination.
    case openMail(messageID: String?)
    /// List the course notebooks under the school folder (quick actions phase 5) — a single
    /// read-only `course.list` tool call. The folders on disk are the course list, so a course
    /// added by hand in Obsidian is reported without any import step.
    case listCourses(limit: Int?)
    /// Create one templated note in a course (quick actions phase 5) — a single
    /// `course.note.create` tool call, minting the course folder on first use. The caller names a
    /// **course**, never a folder: the adapter derives the folder inside the school root, so a
    /// note can only ever land there.
    case createCourseNote(course: String, title: String)
    /// Open a Google search for the query in the browser (NIC-134) — a single `google.search`
    /// tool call. The host is fixed to google.com by the adapter; only the query varies.
    case googleSearch(query: String)
    /// Open a YouTube search for the query in the browser (quick-actions phase 4) — a single
    /// `youtube.search` tool call. The host is fixed to youtube.com by the adapter; only the
    /// query varies.
    case youtubeSearch(query: String)
    /// Clone a git repository into the projects root (quick-actions phase 4) — a single
    /// `git.clone` tool call. `directory` is the optional folder under that root; the adapter
    /// derives one from the repository name when it is nil, and re-checks containment either way.
    /// The `clone <url>` grammar produces a nil directory; the form can supply one.
    case cloneRepository(url: String, directory: String?)
    /// Create one Linear issue — a single `linear.createissue` tool call, from the `create-ticket`
    /// Input form. Like ``createCalendarEvent`` the parser never produces it: no text grammar
    /// carries a title, a body, a team, a project, a label and a priority without becoming lossy.
    case createLinearIssue(LinearIssueDraft)
    /// Create one Spotify playlist — a single `spotify.createplaylist` tool call, from the
    /// `create-playlist` Input form. Form-submitted only: no text grammar carries a name, a
    /// description and a visibility choice without becoming lossy about quoting.
    case createSpotifyPlaylist(name: String, description: String?, isPublic: Bool)
    /// Scaffold a new project folder — a single `project.scaffold` tool call, from the
    /// `create-project` Input form. Form-submitted only.
    case scaffoldProject(name: String, location: String?, summary: String?, importance: Int?)
    /// Send one iMessage — a single `messages.send` tool call, from the `send-text` Input form.
    /// Form-submitted only, and the one intent that always reaches a confirmation.
    case sendMessage(MessageDraft)
    /// Control the user's Spotify playback (NIC-133) — a single `spotify.control` tool call. The
    /// action is one of play/pause/next/previous; the adapter sends it to the active device.
    case spotifyControl(action: String)
    /// Open an https web address in the browser (NIC-127) — a single `web.open` tool call, used
    /// for news article links. The adapter validates the scheme/host; a non-https link is refused.
    case webOpen(url: String)
    /// Create one calendar event — a single `calendar.createevent` tool call, from the
    /// `create-event` Input form.
    ///
    /// The parser never produces this: there is no text grammar that could carry a title, two
    /// datetimes, a calendar, a location and notes without becoming lossy and ambiguous about
    /// quoting. It is reached through ``CommandRuntime/submit(intent:source:summary:)``, which
    /// skips parsing and nothing else — the same policy, confirmation, disclosure and lifecycle
    /// still apply.
    case createCalendarEvent(CalendarEventDraft)
    case runHook(ReferenceEntry)
    /// Measure current internet download/upload capacity on request (NIC-135) —
    /// a single read-only `network.speed.test` tool call.
    case runSpeedTest
    /// Run a configured workflow / quick action (an ordered plan of tool steps
    /// resolved by the action planner).
    case runAction(actionId: String)
    /// List installed applications, read-only (NIC-119 discovery — feeds the
    /// More Apps picker; never launches anything).
    case listApps
    /// Quit every open regular application across all modes (NIC-143) — a single
    /// destructive, confirmation-gated `apps.quitall` tool call.
    case quitAllApps
}

/// The outcome of parsing one line of direct input.
///
/// Only ``parsed(_:)`` may proceed to execution. ``unrecognized(_:)`` and
/// ``ambiguous(_:)`` both mean "do not execute" — the parser never guesses.
public enum ParseResult: Equatable, Sendable {
    case parsed(CommandIntent)
    case unrecognized(UnrecognizedInput)
    case ambiguous(AmbiguousReference)
}

/// Input that did not resolve to an intent, with suggestions for the user.
public struct UnrecognizedInput: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case emptyInput
        case unknownVerb(String)
        case missingArgument(verb: String)
        case unresolvedReference(verb: String, token: String)
    }

    public let reason: Reason
    public let suggestions: [String]

    public init(reason: Reason, suggestions: [String]) {
        self.reason = reason
        self.suggestions = suggestions
    }
}

/// A reference that matched more than one catalog and is therefore ambiguous —
/// a reviewable error rather than an executed command.
public struct AmbiguousReference: Equatable, Sendable {
    public struct Candidate: Equatable, Sendable {
        /// The catalog the token matched, e.g. `"app"` or `"url"`.
        public let kind: String
        public let id: String

        public init(kind: String, id: String) {
            self.kind = kind
            self.id = id
        }
    }

    public let verb: String
    public let token: String
    public let candidates: [Candidate]

    public init(verb: String, token: String, candidates: [Candidate]) {
        self.verb = verb
        self.token = token
        self.candidates = candidates
    }
}

/// The typed values a `create-event` form collected (docs/quick-actions/PLAN.md phase 3).
///
/// Times are LOCAL WALL-CLOCK ISO strings (`2026-08-03T14:00:00`), matching the calendar read
/// side (NIC-126): the time a user typed is the time they meant, and the platform adapter resolves
/// it in the host's zone. Optional fields are omitted rather than defaulted, so nothing is
/// invented on the user's behalf.
/// Everything the `create-ticket` form collected (quick-actions phase 4). Team is not optional and
/// is never inferred: a workspace can have several teams, and guessing one would file the ticket
/// somewhere the user did not choose. `teamName`/`projectName`/`labelName` ride along purely so a
/// confirmation can name the destination in words — an id alone is unreadable in a prompt. Labels
/// are a list because a Linear issue routinely carries several (a category and a status).
public struct LinearIssueDraft: Equatable, Sendable {
    public let title: String
    public let description: String?
    public let teamID: String
    public let teamName: String?
    public let projectID: String?
    public let projectName: String?
    public let labelIDs: [String]
    public let labelNames: [String]
    /// Linear's scale: 0 none, 1 urgent, 2 high, 3 medium, 4 low. Nil leaves it unset.
    public let priority: Int?

    public init(
        title: String,
        description: String? = nil,
        teamID: String,
        teamName: String? = nil,
        projectID: String? = nil,
        projectName: String? = nil,
        labelIDs: [String] = [],
        labelNames: [String] = [],
        priority: Int? = nil
    ) {
        self.title = title
        self.description = description
        self.teamID = teamID
        self.teamName = teamName
        self.projectID = projectID
        self.projectName = projectName
        self.labelIDs = labelIDs
        self.labelNames = labelNames
        self.priority = priority
    }
}

/// Everything the `send-text` form collected.
///
/// `targetName` and `groupSize` exist purely for the confirmation: a phone number tells the reader
/// nothing, and "9 people" is the difference between a message and a broadcast (FR-SAF-04).
public struct MessageDraft: Equatable, Sendable {
    public let body: String
    public let target: String
    /// `participant` (one person) or `chat` (an existing thread).
    public let targetKind: String
    public let targetName: String?
    public let groupSize: Int?

    public init(
        body: String, target: String, targetKind: String, targetName: String? = nil, groupSize: Int? = nil
    ) {
        self.body = body
        self.target = target
        self.targetKind = targetKind
        self.targetName = targetName
        self.groupSize = groupSize
    }
}

public struct CalendarEventDraft: Equatable, Sendable {
    public let title: String
    public let startsAt: String
    public let endsAt: String
    public let calendarID: String?
    public let calendarTitle: String?
    public let location: String?
    public let notes: String?

    public init(
        title: String,
        startsAt: String,
        endsAt: String,
        calendarID: String? = nil,
        calendarTitle: String? = nil,
        location: String? = nil,
        notes: String? = nil
    ) {
        self.title = title
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
        self.location = location
        self.notes = notes
    }
}
