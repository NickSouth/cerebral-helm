---
title: CerebralHelm North Star
document_type: product-vision
status: active
date: 2026-06-23
authority: long-term-product-intent
---

# CerebralHelm North Star

> This document defines long-term product intent. The MVP PRD is authoritative for current scope and naming when the two documents differ.

**CerebralHelm** is a local-first agentic desktop environment for macOS, centered around a voice assistant named **Heimlich** and extended by an iOS companion app. It is not a replacement operating system; it is a personal command layer that runs on top of macOS and turns the Mac into an intelligent, context-aware workspace.

The goal is to make CerebralHelm the front door to my digital life: a persistent dashboard, command palette, voice interface, memory system, and agent launcher that can route natural-language commands to local tools, cloud models, native macOS automation, Google Workspace, personal notes, and project-specific agents.

Heimlich is the personality and interaction layer. CerebralHelm is the environment.

## **Core Vision**

CerebralHelm gives me one surface through which I can control my computer, manage my work, capture thoughts, launch agents, and move between different modes of life.

Instead of opening apps manually, searching through files, checking scattered notifications, remembering where I left off, and switching contexts myself, I can say or type what I want:

> “Heimlich, switch to Developer mode.”  
> “Summarize my important emails.”  
> “Open the CerebralHelm project context.”  
> “Add this idea to my project inbox.”  
> “What do I have due today?”  
> “Book me a tee time tomorrow, but ask before confirming.”  
> “Text Mom that I’m leaving now.”

CerebralHelm should feel like a futuristic command center, but its real value is practical: fewer context switches, faster capture, better organization, and a personalized agent layer that understands my tools, projects, schedule, and workflows.

## **What It Is**

CerebralHelm is:

- A local-first agentic desktop assistant for macOS.

- A persistent dashboard and command environment.

- A router between local models, cloud models, and deterministic tools.

- A personal knowledge base backed by files, SQLite, and semantic search.

- A launchpad for specialized agents such as research, studying, finance, coding, and planning.

- A macOS automation layer for opening apps, arranging windows, changing modes, and triggering workflows.

- A Google Workspace-aware assistant for Gmail, Calendar, Drive, Docs, Tasks, and Contacts.

- A voice-first interface through Heimlich.

- A mobile companion system through an iOS app.

It is explicitly **not** a literal operating system. macOS remains underneath: Finder, WindowServer, app permissions, Spaces, and system security still exist. CerebralHelm is the power-user layer above them.

## **Desktop Experience**

On Mac, CerebralHelm lives as a desktop-level environment.

It has three main UI layers:

1. **Backdrop Dashboard:** A futuristic, functional dashboard pinned behind normal app windows. It behaves like an interactive desktop surface, showing current mode, projects, calendar, tasks, system status, agent activity, and quick actions.
2. **Command Palette:** A global hotkey interface for typing commands, launching workflows, searching, asking questions, and running tools.
3. **Heimlich Panel:** A compact floating assistant panel that can appear over apps and potentially over fullscreen Spaces. It can be triggered by keyboard shortcut, voice, or mouse edge/corner gesture. It gives access to quick commands like exiting fullscreen, opening the dashboard, switching modes, starting voice input, or launching common views.

The dashboard should adapt to different monitor setups. On a desk monitor, it can be a full command-center layout. On the laptop screen, it can become a compact status/control surface. If monitors are connected or disconnected, CerebralHelm should reflow automatically.

## **Modes**

CerebralHelm supports named modes that change the computer’s working context.

The canonical modes are Executive, Developer, School, and Entertainment.

**Executive Mode**

- Surface the daily schedule, priorities, current projects, and system health.

- Provide cross-project briefing and planning controls.

- Expose all four configured agent surfaces at an appropriate summary level.

**Developer Mode**

- Open VSCode, Terminal, GitHub, docs, local project dashboard.

- Start relevant dev servers or shell hooks.

- Arrange windows across monitors.

- Surface active project notes, todos, and recent commits.

- Show focused developer widgets.

**School Mode**

- Open Canvas, calendar, notes, assignments, PDFs, and study tools.

- Show due dates, upcoming exams, and class-specific materials.

- Launch studying or summarization agents.

**Entertainment Mode**

- Open entertainment, music, games, fantasy football, golf tools, or social apps.

- Reduce work widgets.

- Change the dashboard to a lighter layout.

Modes are not just visual themes. They are combinations of window layouts, apps, tools, widgets, context, and automation.

## **Context Awareness and Attention Support**

CerebralHelm should understand the immediate workspace when I explicitly invite it, and it may offer opt-in attention support during focused workflows.

**Screen context on invocation.** When Heimlich is activated, CerebralHelm should be able to capture the active window or screen as temporary context. This makes commands such as "add this Canvas assignment to my calendar" possible without requiring me to restate the assignment title, due date, instructions, or page URL.

Screen context should be invocation-scoped rather than continuous by default. The UI should clearly indicate when a capture occurs, support per-app allow and deny rules, prefer on-device OCR or vision processing, and discard the image after extracting the needed context unless I intentionally save it. Sending a screenshot or extracted content to a cloud model must follow the environment's privacy policy. Any resulting write action, such as creating the calendar event, still follows the normal confirmation policy.

**Attention-aware sessions.** During an explicitly started study, reading, or development session, CerebralHelm may use camera-based eye tracking and other local session signals to estimate likely attention drift. If the evidence is sustained, Heimlich can offer a lightweight suggestion such as: "Your attention seems to be decreasing. Consider a 10-minute break, then come back."

Attention estimates are heuristics, not facts or medical measurements. Eye tracking must be opt-in, visibly active, processed locally by default, disabled for sensitive apps or environments, and easy to pause. Prompts should require sustained signals, use cooldowns, learn from dismissals, and never become punitive, manipulative, or a hidden productivity score.

The durable abstraction is a bounded perception layer. Screen capture, OCR, active-app metadata, and attention estimation should produce minimal structured, short-lived context for Heimlich; agents should not receive an unrestricted continuous camera or screen feed.

## **Agent Layer**

CerebralHelm routes requests through an agent runtime.

Simple, low-risk tasks can be handled locally or deterministically. Complex tasks can be escalated to a stronger cloud model such as Claude through the Claude Agent SDK.

The agent runtime should decide:

- Is this a simple tool command?

- Is this a local-model task?

- Does this require Claude-level reasoning?

- Does this require user confirmation?

- What context should be retrieved from memory?

- Which tool or agent should handle the request?

The system should not be one giant agent with unlimited power. It should be a safe orchestrator that calls narrow, explicit tools.

## **Tool Layer**

CerebralHelm’s capabilities are exposed through small tools, ideally as MCP servers or MCP-compatible services.

Example tools:

- app.open

- url.open

- url.open_on_display

- hook.run

- note.capture

- note.search

- calendar.list_today

- calendar.create_event_draft

- gmail.summarize_important

- gmail.create_reply_draft

- drive.search_files

- tasks.create_task

- contacts.resolve_person

- system.status.read

- system.set_volume

- system.get_displays

- mode.apply

- window.arrange

- companion.capture_note

- context.capture_active_window

- context.extract_visible_content

- attention.get_session_signal

The dashboard does not directly control the system. It sends intent to the runtime. The runtime calls tools. Tools touch macOS, APIs, files, databases, or external systems.

That separation keeps CerebralHelm extensible, testable, and safer.

## **Google Workspace Integration**

Google Workspace is a first-class integration.

CerebralHelm should eventually connect to:

- Gmail

- Google Calendar

- Google Drive

- Google Docs

- Google Sheets

- Google Tasks

- Google Contacts

Core use cases:

- Summarize important unread emails.

- Detect emails that need action.

- Draft replies for approval.

- Search old emails and threads.

- Show today’s calendar.

- Find free time.

- Create calendar events with confirmation.

- Search Drive files.

- Summarize Docs.

- Pull project/class context from folders.

- Add tasks.

- Resolve contacts for texting or emailing.

Dangerous actions should be confirmation-gated. Reading, summarizing, and drafting can be low-friction. Sending emails, deleting messages, booking events, or changing important data should require explicit approval.

## **Memory and Knowledge Base**

CerebralHelm has a persistent personal knowledge base.

The memory system should be hybrid:

1. **Markdown file hierarchy:** Human-readable source of truth for notes, ideas, project plans, class notes, and personal thinking.
2. **SQLite database:** Structured data for tasks, habits, finances, logs, calendar metadata, tool usage, and mode history.
3. **Vector index:** Disposable semantic index over the Markdown files and selected structured records.

The source of truth is not the vector database. The files and SQLite data are the truth; embeddings are only a search layer.

The system should not capture everything automatically. It should prefer intentional notes, useful logs, and curated context. When escalating to cloud models, it should send only the relevant retrieved slice, not the entire knowledge base.

## **System Status and Custom UI Layer**

CerebralHelm can display its own abstraction over system state.

It cannot truly replace the native macOS menu bar, Control Center, or top bar, but it can hide or ignore them and render its own system layer.

Possible custom widgets:

- Mac battery

- charging state

- Wi-Fi/network status

- volume

- audio output device

- Bluetooth device status

- display layout

- current mode

- current project

- calendar

- tasks

- agent activity

- phone connection status

- laptop/phone battery if available

- CPU/memory/disk usage

The result is a CerebralHelm-native status bar/dashboard that is more personal and useful than the default macOS top bar.

## **iOS Companion App**

The iOS companion app is part of the north star.

The Mac remains the main brain. The iPhone app is the mobile capture and remote-control surface.

The companion app should let me:

- Capture notes quickly.

- Record voice notes.

- Send commands to the Mac.

- Add reminders or tasks.

- Store project ideas.

- View cached project context.

- See today’s schedule.

- Trigger agent tasks remotely.

- Receive summaries from the Mac.

- Sync phone status, such as battery, when possible.

- Use Heimlich while away from the laptop.

The companion app should not try to be the full desktop agent. It should be lightweight.

Ideal architecture:

- iPhone handles capture, push-to-talk, quick commands, cached context, and mobile notifications.

- Mac handles heavy agents, local models, memory, tools, and desktop automation.

- Cloud models are used when needed for reasoning-heavy tasks or when away from the Mac.

Connection options include local network, Multipeer Connectivity, iCloud sync, and possibly Shortcuts/App Intents. AirDrop is not the primary architecture.

## **Voice Assistant: Heimlich**

Heimlich is the voice interface and personality layer for CerebralHelm.

Voice should be push-to-talk or explicitly triggered, not always-listening by default. The system should support:

- Speech-to-text

- Intent routing

- Tool execution

- Spoken responses

- Optional confirmation for risky actions

Heimlich should be able to operate on both Mac and iPhone, but in different forms.

On Mac, Heimlich can control the desktop, launch apps, use tools, and interact with the dashboard.

On iPhone, Heimlich is mostly for capture, quick commands, reminders, project notes, and sending requests back to the Mac.

## **What Should Be Possible**

CerebralHelm should eventually support:

- “Text Mom \_\_\_.”

- Login greetings based on time of day and schedule.

- Dev/school/fun modes.

- Window arrangement across monitors.

- App and URL launching.

- Calendar summaries and event creation.

- Gmail summaries and suggested replies.

- Important-email awareness.

- Notification-like summaries from source APIs.

- Project dashboards.

- Research agents.

- Study agents.

- Finance planning agents.

- Personal note capture.

- Project idea capture.

- Mobile note capture through iPhone.

- Local/cloud LLM routing.

- System-status dashboard.

- Voice commands.

- Fullscreen Heimlich overlay/panel.

- Invocation-scoped screen context for voice and typed commands.

- Opt-in attention-aware study and development sessions.

- Confirmation-gated actions like sending, booking, deleting, purchasing, or running risky commands.

## **What Is Not the Goal**

CerebralHelm should not try to:

- Replace macOS itself.

- Bypass Apple permissions.

- Fully replace the native menu bar or Control Center.

- Scrape banks or store bank passwords.

- Autonomously spend money without confirmation.

- Silently send messages or emails.

- Become a fragile browser bot for every website.

- Run as an always-listening iPhone daemon.

- Treat a local small model as reliable enough for every complex task.

- Dump all personal data into one vector database.

The best version is powerful because it is structured, not because it is reckless.

## **Safety Model**

CerebralHelm should follow a trust gradient.

Low-risk actions can run directly:

- Open app.

- Search notes.

- Show calendar.

- Summarize email.

- Add note.

- Switch mode.

- Display system status.

Medium-risk actions can prepare drafts:

- Draft email.

- Draft text message.

- Prepare calendar event.

- Prepare booking.

- Suggest financial plan.

- Stage file operation.

High-risk actions require confirmation:

- Send message.

- Send email.

- Delete/archive important data.

- Run shell commands.

- Push code.

- Book tee time.

- Spend money.

- Change financial data.

- Modify calendar significantly.

- Share private context with cloud models.

The agent should be helpful by getting me most of the way there, then stopping exactly where human approval matters.

## **North Star Summary**

CerebralHelm is the personalized command layer I wish macOS had: a local-first, model-agnostic, voice-enabled desktop environment that knows my projects, tools, schedule, notes, and workflows.

The Mac app is the command center. The iOS app is the pocket companion. Heimlich is the voice and personality. The tool layer is the power. The knowledge base is the memory.

The final product should feel like I am not just using a laptop — I am operating a personal agentic workspace that can see my context, organize my work, prepare actions, run workflows, and help me move through school, software projects, finances, research, and daily life with less friction.
